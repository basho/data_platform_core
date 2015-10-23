# BDP Cache Proxy #
## Service Manager Control ##
### Layout ###

 Path             | Purpose                                                  
------------------|---------------------------------
 ./               | Control scripts, UX                                      
 ./bin/           | Binaries, executed from control scripts                  
 ./config/        | Configuration, generated                                 
 ./log/           | Log files, generated from runs                           
 ./run/           | Pid files, generated from runs                           

### Quickstart ###
#### Start the Service ####
1. Copy the binaries to the bin subdirectory.
2. Execute
```bash
./run.sh
```
##### Exceptions #####
* If the service is already running, which is detected by using a pid file, the
service may not be re-run.

#### Stop the Service ####
1. Execute
```bash
./stop.sh
```

##### Exceptions #####
* If the service is not already running, which is detected by using a pid file,
the service stop request is a nop.

### Environment Variables ###

 Name                    | Brief                           | Default         
-------------------------|---------------------------------|---------------------
 HOST                    | Ip to listen on                 | 0.0.0.0         
 CACHE_PROXY_PORT        | Port to listen on               | 22122           
 CACHE_PROXY_BIN         | Path to binary                  | ./bin/nutcracker 
 CACHE_PROXY_CONFIG      | Path to config                  | ./config/cache_proxy_$CACHE_PROXY_PORT 
 REDIS_SERVERS           | Ip:Port listing of Redis servers| 127.0.0.1:6379 
 RIAK_KV_SERVERS         | Ip:Port listing of Riak KV servers, (pb_port) | 127.0.0.1:8087 
 CACHE_TTL               | Cache time to live (TTL), may be specified with units, ie 15s for 15 seconds | "15s" 
 CACHE_PROXY_PID         | Path to pid file                | ./run/cache_proxy_$CACHE_PROXY_PORT.pid |
 CACHE_PROXY_RUN_LOG     | Path to stdout log              | ./log/cache_proxy_$CACHE_PROXY_PID.log |
 CACHE_PROXY_ERROR_LOG   | Path to stderr log              | ./log/cache_proxy_$CACHE_PROXY_PID.error.log |

* NOTE: use of CACHE_PROXY_PORT throughout allows for running multiple
Cache Proxy services without colliding on file names
