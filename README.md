## Irmin Regression Tests

### Overhead

This tester dumps message of size for cnt times:

```
overhead -ascii[-u] | -image[-u] size -cnt number
```

Adding “-u” makes the message unique. So to dump 20,000 unique
messages of size 100 bytes you run:

```
overhead -ascii-u 100 -cnt 20_000.
```

### Search

```
search -samples num
```

This search tester will get all first level keys under the “root” key
and will do `num` random access.