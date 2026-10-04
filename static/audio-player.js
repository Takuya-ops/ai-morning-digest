// Audio playback is disabled. Remove controls from previously cached pages.
document.querySelectorAll('audio').forEach(audio => { audio.pause(); audio.removeAttribute('src'); audio.load(); });
document.getElementById('briefing-player')?.remove();
