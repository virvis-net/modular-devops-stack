import { createRouter, createWebHistory } from 'vue-router';
import { recordFunnelNavigation } from './telemetry.js';
import StartView from './views/StartView.vue';
import DetailsView from './views/DetailsView.vue';
import CompleteView from './views/CompleteView.vue';

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', name: 'start', component: StartView },
    { path: '/details', name: 'details', component: DetailsView },
    { path: '/complete', name: 'complete', component: CompleteView },
  ],
});

router.afterEach((to) => {
  recordFunnelNavigation(String(to.name ?? 'unknown'));
});

export default router;
