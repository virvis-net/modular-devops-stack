<script setup>
import { ref } from 'vue';

const interest = ref('');
</script>

<template>
  <section class="panel">
    <p class="eyebrow">Step 02 · Explore</p>
    <h1>What would you like to improve?</h1>
    <p class="intro">Choose an example topic. This selection stays in the browser and is not sent to the API.</p>

    <label class="field-label" for="interest">Choose a topic</label>
    <select id="interest" v-model="interest" class="select">
      <option disabled value="">Select one</option>
      <option>Understand customer journeys</option>
      <option>Improve service reliability</option>
      <option>Shorten feedback loops</option>
    </select>

    <div class="actions">
      <RouterLink class="button button-secondary" to="/">Back</RouterLink>
      <RouterLink v-if="interest" class="button" to="/complete">
        Continue <span aria-hidden="true">→</span>
      </RouterLink>
      <button v-else class="button" disabled>Continue <span aria-hidden="true">→</span></button>
    </div>
  </section>
</template>
