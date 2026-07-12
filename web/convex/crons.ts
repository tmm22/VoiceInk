import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

crons.interval(
  "delete expired anonymous transcripts",
  { minutes: 5 },
  internal.cleanup.deleteExpiredAnonymousTranscriptions,
);

export default crons;
