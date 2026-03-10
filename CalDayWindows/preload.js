// Preload script: runs before the web page loads.
// Sets the plan to "premium" (all features free) and hides billing UI.
window.addEventListener('DOMContentLoaded', () => {
  // Force premium plan — all features unlocked for free
  localStorage.setItem('fukusuke_plan', 'premium');
});
