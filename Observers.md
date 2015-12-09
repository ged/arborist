# Observers

## Subscription

Get node change delta events for every 'host' type node.

    {
        action: subscribe,
        version: 1,
        event_type: node.delta
    },
    {
        type: 'host',
    }

Get a snapshot of node state on every update for 'service' type nodes under
the 'bennett' node.

    {
        action: subscribe,
        version: 1,
        event_type: node.update,
        identifier: 'bennett'
    },
    {
        type: 'service',
    }

Get events of state changes to services running on port 80.

    {
        action: subscribe,
        version: 1,
        event_type: node.delta
    },
    {
        type: 'service',
        port: 80
    }

Get notified of every system event (startup, shutdown, reload, etc.)

    {
        action: subscribe,
        version: 1,
        event_type: sys.*
    },
    Nil



subscription
    * Event to subscribe to
    * Node to attach subscription to.  No node means 'root', which sees all subnode events.
    * One or more action blocks

Actions have:
    * a block to execute
    * Zero or more time-periods, which are unioned together. No time periods means anytime.

Pragmas:
    * Summarize:
      (send a single alert summarizing every event received over x period of time, or n events)
    * Squelch:


:MAHLON:
    The manager should probably serialize subscriptions for its nodes. Otherwise the manager
    can restart and any running observers will never again receive events because the
    subscriptions will have disappeared.




