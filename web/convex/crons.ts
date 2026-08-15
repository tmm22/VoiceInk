import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

crons.interval(
  "delete expired transcripts",
  { minutes: 5 },
  internal.cleanup.deleteExpiredTranscriptions,
  {},
);

export default crons;
