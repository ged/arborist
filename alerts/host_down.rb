# -*- ruby -*-
#encoding: utf-8

require 'arborist'


Arborist::Alert 'host down' do

	alerter( :mail ) do
		mail 'ops@cozy.co', rollup: 2, in: 30.seconds
	end
	alerter( :sms ) do
		run 'send_sms', only: 1, after: 15m
	end

	on :state_change do
		match status: :down
		match tag: filemaker

		after 6
			alerter :mail, :sms
		end

	end


	on :state_change do
		match status: :down

		timeperiod '8AM' .. '6PM' do
		end

		exclude tag: filemaker !important

		alerter :mail

	end

end


Arborist::Alert 'status reports' do

	on :periodic do
		match (failures % 5).nonzero?
	end

	on :periodic do
		after 24.hours
		match downtime > 1.hour
		mail 'ops@laika.com'
	end

end