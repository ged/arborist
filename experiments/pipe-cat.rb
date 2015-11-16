#!/usr/bin/env ruby

child_stdin, parent_writer = IO.pipe
parent_reader, child_stdout = IO.pipe
parent_err_reader, child_stderr = IO.pipe

Process.spawn( 'cat', out: child_stdout, in: child_stdin, err: child_stderr )

child_stdin.close
child_stdout.close
child_stderr.close

rand( 200 ).times do |i|
	parent_writer.puts "Foom #{i}."
end
parent_writer.close

parent_reader.each_line do |line|
	puts "Read: #{line}"
end



