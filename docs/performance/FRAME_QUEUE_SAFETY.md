# Frame queue safety

All real-time queues must be bounded. CastSprint now enforces:

- newest-frame capture behavior;
- nonblocking Metal admission;
- finite drawable pool;
- finite audio schedule depth;
- finite recording submission depth;
- no hidden OBS render target.

Drops are preferable to latency growth or system-wide memory pressure. Renderer drops are exposed through `PipelineTelemetry.renderBackpressureDrops`. A future diagnostics panel should expose audio and recording drops as well.

