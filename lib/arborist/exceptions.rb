# -*- ruby -*-
#encoding: utf-8


# Arborist namespace
module Arborist

	class ClientError < RuntimeError; end

	class MessageError < ClientError

		def initialize( reason )
			super( "Invalid message (#{reason})" )
		end

	end

	class ServerError < RuntimeError; end

	class NodeError < RuntimeError; end

	class ConfigError < RuntimeError; end

end # module Arborist

