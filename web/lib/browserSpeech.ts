// Adapted from tmm22/untitled-folder-2 web/src/lib/browserSpeech/controller.ts.
export type BrowserVoice = {
  id: string;
  name: string;
  language: string;
  isLocal: boolean;
  isDefault: boolean;
};

export type BrowserSpeechRequest = {
  text: string;
  voiceId?: string;
  rate: number;
  pitch: number;
  volume: number;
};

const supported = () => typeof window !== "undefined" && "speechSynthesis" in window;
const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

async function waitForVoices(timeoutMs = 1500): Promise<SpeechSynthesisVoice[]> {
  if (!supported()) return [];
  const synth = window.speechSynthesis;
  const existing = synth.getVoices();
  if (existing.length) return existing;

  return new Promise((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      const voices = synth.getVoices();
      if (!voices.length) return;
      settled = true;
      synth.removeEventListener("voiceschanged", finish);
      resolve(voices);
    };
    synth.addEventListener("voiceschanged", finish);
    setTimeout(() => {
      if (settled) return;
      settled = true;
      synth.removeEventListener("voiceschanged", finish);
      resolve(synth.getVoices());
    }, timeoutMs);
  });
}

export async function loadBrowserVoices(): Promise<BrowserVoice[]> {
  const voices = await waitForVoices();
  return voices.map((voice) => ({
    id: voice.voiceURI || voice.name,
    name: voice.name,
    language: voice.lang || "Unknown",
    isLocal: voice.localService,
    isDefault: voice.default,
  }));
}

class BrowserSpeechController {
  private current: SpeechSynthesisUtterance | null = null;
  private lastRequest: BrowserSpeechRequest | null = null;

  speak(request: BrowserSpeechRequest): Promise<void> {
    if (!supported()) return Promise.reject(new Error("Speech synthesis is unavailable"));
    const synth = window.speechSynthesis;
    this.cancel();
    this.lastRequest = request;

    return new Promise((resolve, reject) => {
      const utterance = new SpeechSynthesisUtterance(request.text);
      const voice = synth.getVoices().find(
        (candidate) => candidate.voiceURI === request.voiceId || candidate.name === request.voiceId,
      );
      if (voice) utterance.voice = voice;
      utterance.rate = clamp(request.rate, 0.2, 2.5);
      utterance.pitch = clamp(request.pitch, 0.1, 2);
      utterance.volume = clamp(request.volume, 0, 1);
      utterance.onend = () => {
        this.current = null;
        resolve();
      };
      utterance.onerror = (event) => {
        this.current = null;
        reject(new Error(event.error || "Speech synthesis failed"));
      };
      this.current = utterance;
      synth.speak(utterance);
    });
  }

  pause() {
    if (supported() && window.speechSynthesis.speaking) window.speechSynthesis.pause();
  }

  resume() {
    if (supported() && window.speechSynthesis.paused) window.speechSynthesis.resume();
  }

  cancel() {
    if (supported() && (this.current || window.speechSynthesis.speaking)) window.speechSynthesis.cancel();
    this.current = null;
  }
}

let sharedController: BrowserSpeechController | null = null;

export function getBrowserSpeechController() {
  if (!supported()) throw new Error("Speech synthesis is unavailable");
  sharedController ??= new BrowserSpeechController();
  return sharedController;
}
