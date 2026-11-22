# Local Aptabase changes

Upstream: aptabase/aptabase-swift 0.4.0, revision a1ee53e99478921cd166c40f59f2e41271032776.
The upstream MIT license is retained in LICENSE.

- Codable prepared events retain SDK sessions and original system properties.
- A dedicated awaitable send reports HTTP acceptance for one event; it bypasses the periodic queue.
- A consent epoch fences delayed enqueue tasks, activation/termination polling, and requests.
- Pausing cancels only SDK-owned request tasks, including those using URLSession.shared.
- Queue clearing invalidates failed in-flight flushes so they cannot requeue discarded events.
- Session ID state is synchronized.
- The package has no documentation-plugin dependency, allowing offline local builds.

Milestone persistence and retry ownership live in NumWorks, not this SDK.
