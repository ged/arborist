# Observers

## Filters

### state change

- when a host `status` changes from `up` to `down`
- when a host `status` changes from `down` to `up`
- every time a webservice `response_status` changes


## Actions

...but don't send more than 5 mails per hour.
...but don't send more than 3 SMSes per hour.


SUBSCRIBE /nodes/bennett Arborist/0.1
{
    type: service
    port: 80
}

=>
200 OK
7d4083bc35a9


SUBSCRIBE /nodes Arborist/0.1
{
    type: service
    port: 80
}

=>
200 OK
7d4083bc35a9

