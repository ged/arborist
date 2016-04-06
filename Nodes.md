# Nodes



    Arborist::Host 'sidonie' do
    	parent 'duir'
    	description "NAS and media server"
    	address '192.168.16.3'
    
    	tags :infrastructure,
    	     :storage,
    	     :media,
    	     :rip_status_check
    
    	service 'ssh'
    	service 'demon-http', port: 6666, protocol: 'http'
    	service 'postgresql'
    
    	service 'smtp'
    
    	service 'http',
            depends_on: 'postgresql'
    	service 'sabnzbd', port: 8080, protocol: 'http'
    	service 'sickbeard', port: 8081, protocol: 'http'
    	service 'pms', port: 32400, protocol: 'http'
    	service 'couchpotato', port: 5050, protocol: 'http'
    end


    Arborist::Host 'jhereg' do
        parent 'duir'
        description "Directory server"
        address '192.168.16.7'
        
        service 'ldaps'
    end


    Arborist::Host 'webserver' do
    	description "Public webserver"
    	address '54.16.62.181'
    
        service 'http',
            depends_on: 'foo'
            depends_on: all_of( 'postgresql', 'daemon-http', on: 'sidonie' ),
                all_of( 'ldaps', on: 'jhereg' )
    end


An application server depends on one each of the 'http' services and 'ldaps' services
to be up.

    Arborist::Host 'appserver1' do
        description "Public application webserver"
        address '54.16.62.185'
        service 'http',
            depends_on: all_of(
                    any_of( 'http', on: %w[service1 service2 service3] ),
                    any_of( 'ldaps', on: %w[directory1 directory2] ),
                    all_of( 'else', on: 'something' )
                )
    end


[ :all_of,
    [ :any_of, 'service1-http', 'service2-http', 'service3-http' ],
    [ :any_of, 'directory1-ldaps', 'directory2-ldaps' ],
    'something-else'
]

