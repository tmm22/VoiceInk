export const enhancementInstructions = {
  clean: "Correct grammar, punctuation, capitalization, and obvious transcription errors. Remove filler words and false starts only when doing so preserves the speaker's meaning, details, and natural tone. Never invent information.",
  concise: "Make the text substantially clearer and more concise. Remove repetition and unnecessary words while preserving every material fact, name, number, decision, qualification, and action. Never invent information.",
  professional: "Rewrite the text in a polished, confident professional tone suitable for work or client communication. Preserve the original meaning and all material details. Do not add claims, commitments, or facts that were not present.",
  notes: "Turn the text into structured notes with short headings and useful bullet points. Clearly identify decisions and action items when they are actually present. Preserve names, dates, numbers, and qualifications, and never invent information.",
} as const;

export type EnhancementMode = keyof typeof enhancementInstructions;

export function isEnhancementMode(value: unknown): value is EnhancementMode {
  return typeof value === "string" && Object.hasOwn(enhancementInstructions, value);
}
