<script setup>
import { RouterLink, RouterView } from 'vue-router';
</script>

<template>
  <div class="shell">
    <header class="topbar">
      <a class="brand" href="/" aria-label="Funnel demo home">northstar</a>
      <span class="lab-tag">observability lab</span>
    </header>

    <main class="content">
      <nav class="steps" aria-label="Funnel steps">
        <RouterLink to="/" class="step-link">01 <span>Start</span></RouterLink>
        <RouterLink to="/details" class="step-link">02 <span>Explore</span></RouterLink>
        <RouterLink to="/complete" class="step-link">03 <span>Connect</span></RouterLink>
      </nav>
      <RouterView />
    </main>

    <footer>Demo data stays in this browser. No contact details are submitted.</footer>
  </div>
</template>
