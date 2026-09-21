// Panel texts by language. The resource picks the language from the server's
// humalike_ui_language setting; anything unknown renders English.
const TEXTS = {
  en: {
    "title": "Voice settings",
    "close": "Close",
    "status.muted": "MICROPHONE MUTED",
    "status.transmitting": "TRANSMITTING PROXIMITY",
    "status.transmittingCabin": "TRANSMITTING PROXIMITY + CABIN",
    "devices": "Devices",
    "microphone": "Microphone",
    "headphones": "Headphones",
    "defaultDevice": "Default device",
    "defaultMicrophone": "Default microphone",
    "defaultHeadphones": "Default headphones",
    "refreshDevices": "Refresh devices",
    "reconnect": "Reconnect",
    "testOutput": "Test headphones",
    "testInput": "Test microphone (2.5 s)",
    "volume": "Volume",
    "volume.mic": "Speaking volume",
    "volume.npc": "NPC volume",
    "volume.master": "Overall voice volume",
    "volume.radio": "Radio volume",
    "volume.calls": "Phone call volume",
    "soon": "Soon",
    "ptt.title": "Push to talk",
    "ptt.native": "Native push to talk",
    "ptt.nativeHint": "The same key as FiveM's built-in voice",
    "ptt.test": "Hold to test",
    "ptt.failMuted": "Voice is fail-muted: the track stays muted unless push to talk is held.",
    "diagnostics": "Diagnostics",
    "diag.control": "Control plane",
    "diag.media": "Media",
    "diag.routing": "Routing",
    "diag.audio": "AudioContext",
    "diag.sources": "{count} sources",
    "diag.audioIdle": "not started",
    "command": "Command",
    "error.invalidSession": "Invalid voice session",
    "error.sessionFailed": "Could not create a session (HTTP {status})",
    "error.noToken": "The router issued no LiveKit token",
    "error.webrtcConnect": "Could not connect to WebRTC",
    "error.micStart": "Could not start the WebRTC microphone",
    "error.micPermission": "Microphone permission missing. Open F8, accept Capture your microphone, then click Reconnect in /voice.",
    "error.micPrefix": "WebRTC microphone: {message}",
    "error.testOutput": "Headphone test failed",
    "error.testInput": "Microphone test failed",
    "error.connectFirst": "Connect the microphone to voice first.",
    "error.sampleLoad": "Could not load the test sample",
    "error.noRecorder": "This CEF version does not support the microphone test",
    "error.recordFailed": "Could not record the microphone sample",
    "hint.receiving": "WebRTC receiving is active. If FiveM asks for the microphone, open F8 and choose Allow.",
    "hint.micActive": "The WebRTC microphone is active.",
    "hint.recording": "Speak now, recording a 2.5 second sample…",
    "hint.played": "Played the microphone sample on the selected headphones.",
    "hint.outputApplied": "The selected device is active.",
    "hint.outputDefault": "This CEF version uses the default output set in the system/FiveM.",
  },
  pl: {
    "title": "Ustawienia głosu",
    "close": "Zamknij",
    "status.muted": "MIKROFON WYCISZONY",
    "status.transmitting": "NADAJESZ PROXIMITY",
    "status.transmittingCabin": "NADAJESZ PROXIMITY + KABINA",
    "devices": "Urządzenia",
    "microphone": "Mikrofon",
    "headphones": "Słuchawki",
    "defaultDevice": "Domyślne urządzenie",
    "defaultMicrophone": "Domyślny mikrofon",
    "defaultHeadphones": "Domyślne słuchawki",
    "refreshDevices": "Odśwież urządzenia",
    "reconnect": "Połącz ponownie",
    "testOutput": "Test słuchawek",
    "testInput": "Test mikrofonu (2,5 s)",
    "volume": "Głośność",
    "volume.mic": "Głośność mówienia",
    "volume.npc": "Głośność NPC",
    "volume.master": "Głośność całego voice",
    "volume.radio": "Głośność radia",
    "volume.calls": "Głośność rozmów telefonicznych",
    "soon": "Wkrótce",
    "ptt.title": "Przycisk mówienia",
    "ptt.native": "Natywny Push to Talk",
    "ptt.nativeHint": "Ten sam przycisk co wbudowany voice FiveM",
    "ptt.test": "Przytrzymaj, aby przetestować",
    "ptt.failMuted": "Voice jest fail-muted: poza przytrzymaniem PTT track pozostaje wyciszony.",
    "diagnostics": "Diagnostyka",
    "diag.control": "Control plane",
    "diag.media": "Media",
    "diag.routing": "Routing",
    "diag.audio": "AudioContext",
    "diag.sources": "{count} źródeł",
    "diag.audioIdle": "nieuruchomiony",
    "command": "Komenda",
    "error.invalidSession": "Nieprawidłowa sesja voice",
    "error.sessionFailed": "Nie udało się utworzyć sesji (HTTP {status})",
    "error.noToken": "Router nie wydał tokenu LiveKit",
    "error.webrtcConnect": "Nie udało się połączyć z WebRTC",
    "error.micStart": "Nie udało się uruchomić mikrofonu WebRTC",
    "error.micPermission": "Brak zgody na mikrofon. Otwórz F8, zaakceptuj Capture your microphone, potem kliknij Połącz ponownie w /voice.",
    "error.micPrefix": "Mikrofon WebRTC: {message}",
    "error.testOutput": "Test słuchawek nie powiódł się",
    "error.testInput": "Test mikrofonu nie powiódł się",
    "error.connectFirst": "Najpierw połącz mikrofon z voice.",
    "error.sampleLoad": "Nie udało się wczytać próbki testowej",
    "error.noRecorder": "Ta wersja CEF nie obsługuje testu mikrofonu",
    "error.recordFailed": "Nie udało się nagrać próbki mikrofonu",
    "hint.receiving": "Odbiór WebRTC jest aktywny. Jeśli FiveM prosi o mikrofon, otwórz F8 i wybierz Allow.",
    "hint.micActive": "Mikrofon WebRTC jest aktywny.",
    "hint.recording": "Mów teraz — nagrywam próbkę przez 2,5 sekundy…",
    "hint.played": "Odtworzono próbkę mikrofonu na wybranych słuchawkach.",
    "hint.outputApplied": "Wybrane urządzenie jest aktywne.",
    "hint.outputDefault": "Ta wersja CEF używa domyślnego wyjścia ustawionego w systemie/FiveM.",
  },
};

export const LANGUAGES = Object.freeze(Object.keys(TEXTS));
let current = "en";

export function setLanguage(code) {
  const base = String(code ?? "").toLowerCase().split(/[-_]/)[0] ?? "";
  current = Object.hasOwn(TEXTS, base) ? base : "en";
  return current;
}

export function language() {
  return current;
}

export function t(key, params) {
  const text = TEXTS[current][key] ?? TEXTS.en[key] ?? key;
  if (!params) return text;
  return text.replace(/\{(\w+)\}/g, (match, name) => (name in params ? String(params[name]) : match));
}

export function texts(code) {
  return TEXTS[code];
}
