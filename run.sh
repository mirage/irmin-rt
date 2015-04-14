./overhead.native -image-u data/img.jpeg -cnt 5000 -repo /tmp/irmin/test >& overhead.out
./search.native -samples 1000 -repo /tmp/irmin/test >& search.out
