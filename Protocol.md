# Monitors

## Basic Protocol

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


## Commands


### «commandname»

«description»

#### Header

#### Body

#### Return

#### Examples




### status

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


### list

Retrieve an Array of Maps that describes all or part of the node tree. 

#### Required 
 from the node with the specified `identifier`, or the root node if no `identifier` is specified.


Request:

    [
        {
            action: list,
            version: 1
            [from: «identifier»]
            [depth: «arg»]
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



### fetch

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


#### return

- not specified : returns everything.
- `Nil` : returns just identifiers
- array of fields : returns the values of those fields

Search for nodes that match the filter given in the request body, returning a serialized map of node identifiers to requested state.


### update

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


### subscribe

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


### graft

    {
        action: graft,
        version: 1,
        type: 'host',
        identifier: 'joliet',
        parent: 'bennett' # defaults to root
    },
    {
        addresses: [],
        tags: []
    }


### prune

    {
        action: prune,
        version: 1,
        identifier: 'bennett'
    },
    Nil


### modify

    {
        action: modify,
        version: 1,
        identifier: 'bennett'
    },
    {
        addresses: ['10.13.0.22', '10.1.0.23']
    }

