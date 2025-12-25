Run the following shell commands to archive the current plan:

1. Create directory `.claude/archived_plans` if it doesn't exist.
2. Generate a filename based on the current date and the content of the plan (e.g., YYYY-MM-DD_feature-name.md).
3. Move `.claude/plan/PLAN.md` to that new path.
4. Create a new empty `.claude/plan/PLAN.md`.
5. Tell me "Plan archived! Ready for the next task."
