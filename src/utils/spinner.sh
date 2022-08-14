spinner=('\' '-' '/')

for i in `seq 30`; do 
	idx=$((i%3))
	# \r resets the cursor to the beginning of the line.
	((idx == 0)) && echo -e "\rloop"
	echo -en "\r${spinner[idx]}"
	sleep 0.4
done
echo -en "\r "
