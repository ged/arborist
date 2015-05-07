# Monitors


FETCH /nodes/[identifier] Arborist/0.1

SEARCH /nodes Arborist/0.1
{
    status: up
    type: host
    return: address, name
}


UPDATE /nodes Arborist/0.1
Content-type: application/json

{
    duir: {
        pingtime: 0.02
    },
    sidonie: {
        pingtime: 0.28
    }
}

UPDATE /nodes Arborist/0.1
Content-type: application/json

{
    duir: {
        pingtime: null,
        error: "Host unreachable."
    },
    sidonie: {
        pingtime: 0.28
    }
}

UPDATE /nodes/«identifier» Arborist/0.1
{
    duir: {
        acked: «time»,
        acked_by: mahlon
    }
}

