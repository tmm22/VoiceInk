// The Workers AI model behind summaries and text enhancement, shared by the
// ASR Worker (which runs it) and the web routes (which check what it reports).
export const TEXT_GENERATION_MODEL_ID = "@cf/google/gemma-4-26b-a4b-it" as const;
export const TEXT_GENERATION_MODEL_NAME = "gemma-4-26b-a4b-it" as const;
export const TEXT_GENERATION_MODEL_LABEL = "Gemma 4";
