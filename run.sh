rm -rf /tmp/irmin/test/.git
git init /tmp/irmin/test
./overhead.native -image-u data/img.jpeg -cnt 5000 -repo /tmp/irmin/test -repeat 5 -commit-once > overhead.out
./search.native -samples 1000 -repo /tmp/irmin/test > search.out
rm -rf /tmp/irmin/test/.git
git init /tmp/irmin/test
./overhead.native -image-u data/img.jpeg -cnt 5000 -repo /tmp/irmin/test -repeat 5 > overhead1.out
./search.native -samples 1000 -repo /tmp/irmin/test > search1.out
