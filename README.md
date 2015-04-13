## Irmin Regression Tests

### Overhead

This tester dumps message of size for cnt times:

```
overhead -ascii[-u] | -image[-u] size -cnt number [-start number] [-group number] [-commit-once]
```

Adding “-u” makes the message unique. So to dump 20,000 unique
messages of size 100 bytes you run:

```
overhead -ascii-u 100 -cnt 20_000.
```

Adding “-start number” start the key at number. This allows updating the database incrementally.

```
overhead -ascii-u 100 -cnt 20_000 -start 200.
```

Adding “-group number” creates two level key as key1=cnt/number,key2=cnt%number, where the count is the message counter. 

```
overhead -ascii-u 100 -cnt 20_000 -group 100.
```

Adding “-commit-once” creates the view, writes all messages to the view, and then updates the view into the store at the end. By default the view is updated for every messages.

```
overhead -ascii-u 100 -cnt 20_000 -group 100 -commit-once.
```

### Search

```
search -samples num
```

This search tester will get all first level keys under the “root” key
and will do `num` random access.
