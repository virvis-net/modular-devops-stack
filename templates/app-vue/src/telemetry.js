import { context, propagation, SpanKind, SpanStatusCode, trace } from '@opentelemetry/api';
import { W3CTraceContextPropagator } from '@opentelemetry/core';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { BatchSpanProcessor, TracerProvider } from '@opentelemetry/sdk-trace';

const browserResource = resourceFromAttributes({
  'service.name': 'vue-frontend',
});

const traceExporter = new OTLPTraceExporter({
  url: `${window.location.origin}/_otel/v1/traces`,
});

const tracerProvider = new TracerProvider({
  resource: browserResource,
  spanProcessors: [new BatchSpanProcessor({ exporter: traceExporter })],
});

trace.setGlobalTracerProvider(tracerProvider);
propagation.setGlobalPropagator(new W3CTraceContextPropagator());

const tracer = trace.getTracer('modular-devops-stack/vue-funnel');

export function recordPageLoad() {
  const navigation = performance.getEntriesByType('navigation')[0];
  const span = tracer.startSpan('browser.page.load', {
    attributes: {
      'page.path': window.location.pathname,
      'browser.navigation.type': navigation?.type ?? 'unknown',
      'browser.page.load.duration_ms': Math.round(navigation?.loadEventEnd ?? 0),
    },
  });
  span.end();
}

export function recordFunnelNavigation(routeName) {
  const span = tracer.startSpan('funnel.navigation', {
    attributes: {
      'funnel.step': routeName,
    },
  });
  span.end();
}

export async function withFunnelSpan(name, attributes, operation) {
  const parentContext = context.active();
  const span = tracer.startSpan(name, { attributes }, parentContext);
  const spanContext = trace.setSpan(parentContext, span);

  try {
    return await operation(spanContext, span);
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR });
    throw error;
  } finally {
    span.end();
  }
}

export async function getBackendHello(parentContext) {
  const configResponse = await fetch('/runtime-config.json', { cache: 'no-store' });
  if (!configResponse.ok) {
    throw new Error('Could not load frontend runtime configuration');
  }

  const config = await configResponse.json();
  const endpoint = new URL('/api/hello', config.backendApiUrl);
  const clientSpan = tracer.startSpan(
    'GET /api/hello',
    {
      kind: SpanKind.CLIENT,
      attributes: {
        'http.request.method': 'GET',
        'server.address': endpoint.hostname,
        'server.port': Number(endpoint.port || (endpoint.protocol === 'https:' ? 443 : 80)),
        'url.path': endpoint.pathname,
      },
    },
    parentContext,
  );
  const clientContext = trace.setSpan(parentContext, clientSpan);
  const propagationHeaders = {};
  propagation.inject(clientContext, propagationHeaders);

  try {
    const response = await fetch(endpoint, {
      headers: propagationHeaders,
    });
    clientSpan.setAttribute('http.response.status_code', response.status);
    if (!response.ok) {
      clientSpan.setStatus({ code: SpanStatusCode.ERROR });
      throw new Error(`Backend returned HTTP ${response.status}`);
    }
    return await response.json();
  } catch (error) {
    clientSpan.recordException(error);
    clientSpan.setStatus({ code: SpanStatusCode.ERROR });
    throw error;
  } finally {
    clientSpan.end();
  }
}
