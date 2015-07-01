#!/usr/bin/env bash

FPING=/usr/local/bin/fping
declare -a TARGETS

read -r line
echo ${line}

# eval args=($line)
declare -a 'args=('"${line}"')'

while [[ ${#args} -gt 0 ]]; do
	echo "Args: ${#args}: ${args[@]}"
	identifier=${args[0]}
	attrs=${args[@]:1}
	
	for parameter in ${attrs[@]}; do
		echo "Parameter: ${parameter}"
		key=${parameter/=*/}
		value=${parameter/*=/}
		
		echo "Identifier: ${identifier} Key: ${key} Value: ${value}"
	done
	
	read -r line
	# eval args=($line)
	declare -a 'args=('"${line}"')'
done

