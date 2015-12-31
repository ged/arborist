# Observers

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



## Examples

    # -*- ruby -*-
    #encoding: utf-8
    
    require 'arborist'
    
    WORK_HOURS = 'hour {8am-6pm}'
    OFF_HOURS =  'hour {6pm-8am}'
    
    Arborist::Observer "Webservers" do
        subscribe to: 'node.delta',
            where: {
                type: 'service',
                port: 80,
                delta: { status: ['up', 'down'] }
            }
    
        action( during: WORK_HOURS ) do |uuid, event|
            $stderr.puts "Webserver %s is DOWN (%p)" % [ event['data']['identifier'], event['data'] ]
        end
        summarize( every: 5.minutes, count: 5, during: OFF_HOURS ) do |*tuples|
            email to: 'ops@example.com', subject: ""
        end
    
    end



## Schedulability stuff

schedule = Schedule.new
schedule |= Period.time( '8AM' .. '8PM' )
schedule |= Period.day( 'Mon' .. 'Fri' )


# Thymelörde! - An Amazeballs Gem for Doing Stuff With Time™


schedule = Thymelörde!.yes?( 'Tue-Thur {6am-9pm}' )
schedule.ehh? #=> false
schedule.yes? #=> false


Legba -- the gatekeeper?



