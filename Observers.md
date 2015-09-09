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



## Filters

### state change

- when a host `status` changes from `up` to `down`
- when a host `status` changes from `down` to `up`
- every time a webservice `response_status` changes


## Actions

...but don't send more than 5 mails per hour.
...but don't send more than 3 SMSes per hour.


