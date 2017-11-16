# Events

## Event Types

«type».«subtype»

    node.acked
    node.delta
    node.disabled
    node.down
    node.quieted
    node.unknown
    node.up
    node.update
    sys.node_added
    sys.node_removed
    sys.heartbeat


## Event Movement

Propagation

	events being sent up the tree to the root node

Broadcast

	events being sent down to node children

Publishing

	events being sent to subscriptions, including dependent nodes
	triggered via propagation and broadcasting

