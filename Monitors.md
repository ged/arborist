# Monitors

## Protocol

ZMQ REQ socket, msgpack message consisting of an Array of two elements:

    [
        header,
        body
    ]

Header is a Map of the form:

    {
        action: «verb»,     # required
        version: 1,         # required
        [verb-specific attributes]
    }

Body is either Nil or a Map of key-value pairs appropriate to the `action`.


## status

Fetch the status of the Manager.

    {
        action: status,
        version: 1
    }

Response:

    {
        success: true,
        version: 1
    },
    {
        server_version: 0.0.1,
        state: 'running',
        uptime: 17155,
        nodecount: 342
    }


## list

Request:

    [
        {
            action: list,
            version: 1
        }
    ]

Successful response:

    [
        {
            success: true,
            version: 1
        },
        {
            nodes: ''
        }
    ]

failure example:

    [
        {
            success: false,
            reason: "human readable exception message or whatever",
            category: either 'server' or 'client', meaning who is responsible for the error
            version: 1
        }
    ]

Fetch a data structure describing the node tree from the node with the specified
`identifier`, or the root node if no `identifier` is specified.


## fetch

Fetch state for 

    [
        {
            action: search,
            version: 1,
            return: address, name
        },
        {
            status: up
            type: host
        }
    ]

### return

- not specified : returns everything.
- `null` : returns just identifiers
- array of fields : returns the values of those fields

Search for nodes that match the filter given in the request body, returning a serialized map of node identifiers to requested state.


## update

    [
        {
            action: update,
            vresion: 1
        },
        {
            duir: {
                pingtime: 0.02
            },
            sidonie: {
                pingtime: 0.28
            }
        }
    ]

With a failure:

    [
        {
            action: update,
            version: 1
        },
        {
            duir: {
                pingtime: null,
                error: "Host unreachable."
            },
            sidonie: {
                pingtime: 0.28
            }
        }
    ]

