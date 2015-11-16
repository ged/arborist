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

Body is either Nil, a Map of key-value pairs, or an Array of Maps appropriate to the `action`.


## status

Fetch the status of the Manager.

    {
        action: status,
        version: 1,
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
            [from: «identifier»]
        }
    ]

Successful response:

    [
        {
            success: true,
            version: 1
        },
        [
            {
                identifier: 'foo',
                status: 'up',
                parent: '_',
                properties: {},
            },
            {
                identifier: 'bar',
                status: 'down',
                parent: 'foo',
                properties: {},
            }
        ]
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

Fetch the `address`, `description`, and `status` of all nodes.

    [
        {
            action: fetch,
            version: 1,
            include_down: true,
            return: [address, description, status]
        },
        {
            'theon' => {
                address: '10.2.10.4',
                description: 'no theon, reek',
                status: down,
            },
            'thoros' => {
                address: '10.2.10.4',
                description: "The Red God's champion",
                status: up,
            }
        ]
    ]


### return

- not specified : returns everything.
- `Nil` : returns just identifiers
- array of fields : returns the values of those fields

Search for nodes that match the filter given in the request body, returning a serialized map of node identifiers to requested state.


## update

    [
        {
            action: update,
            version: 1
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


## subscribe

    [
        {
            action: subscribe,
            version: 1,
            event_type: 
        },
        [ '28f51427-a160-448b-9051-b2c4f464c5e3' ]
    ]

