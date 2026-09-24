# Scheduling

Deploy the agent, then create a workflow schedule for it with
`OrkesClients#get_scheduler_client`. Agents compile to workflows, so the normal
scheduler applies; there is no agent-specific schedule API.

Use a stable schedule name, a timezone-aware cron, and idempotent input. Pause or
delete the schedule before deleting the agent or stopping its workers.
