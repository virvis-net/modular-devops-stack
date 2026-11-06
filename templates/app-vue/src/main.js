import { createApp } from 'vue';
import App from './App.vue';
import router from './router.js';
import { recordPageLoad } from './telemetry.js';
import './style.css';

const app = createApp(App);
app.use(router);
app.mount('#app');
window.addEventListener('load', recordPageLoad, { once: true });
