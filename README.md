# Http-pixiu

>Target:Regarding http requests as continuations, http-pixiu can directly response without fully digestting.

## Release 
1.0.3 Add feature: yield among requests.
1.0.2 Fix bug: \r\n compatibility... mainly because I don't like \r.
1.0.1 Fix bug: get body with coroutine.
1.0.0 It only implement a static server and I don't know how many bugs it has. But I have to quickly release it to make my own another project work.

## Install

```bash
akku install
bash build.sh
bash .akku/env
```

## Run

```bash
scheme --script run.ss 5000
```

In other bash shell, 
```bash
curl localhost:5000/index.html
```

### Advance

You can also add extra two arguments: expire-time(default 1000 ms) and ticks(default 100000) as follows:
```bash
scheme --script run.ss 5000 1000 100000
```
> Note: Chez Scheme will counts non-leaf s-expression executions and when meet 100000, it will re-enter queue to wait thread to continue job.