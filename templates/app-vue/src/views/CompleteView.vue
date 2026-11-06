<script setup>
import { ref } from 'vue';
import { getBackendHello, withFunnelSpan } from '../telemetry.js';

const loading = ref(false);
const result = ref('');
const error = ref('');

async function sendDemoRequest() {
  loading.value = true;
  result.value = '';
  error.value = '';

  try {
    await withFunnelSpan(
      'funnel.submit_demo',
      { 'funnel.step': 'complete' },
      async (parentContext) => {
        const response = await getBackendHello(parentContext);
        result.value = response.message;
      },
    );
  } catch {
    error.value = 'The API request failed. Check the browser console and the trace in Grafana.';
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <section class="panel">
    <p class="eyebrow">Step 03 · Connect</p>
    <h1>Ready to follow the request?</h1>
    <p class="intro">This sends a demo GET request to the Laravel API. The browser creates spans and propagates trace context with the request.</p>

    <div class="actions">
      <RouterLink class="button button-secondary" to="/details">Back</RouterLink>
      <button class="button" :disabled="loading" @click="sendDemoRequest">
        {{ loading ? 'Calling API…' : 'Send demo request' }}
      </button>
    </div>

    <p v-if="result" class="result" role="status">{{ result }}</p>
    <p v-if="error" class="error" role="alert">{{ error }}</p>
    <p class="caption">The example does not submit or record form values.</p>
  </section>
</template>
