# Mesures V3 — Montée en charge (ApacheBench)
> Scénario V3 — Exigence R3 — Date : _____

## Commande exécutée
```powershell
powershell -ExecutionPolicy Bypass -File tests\Lancer-Tests.ps1 -Scenario V3
# ou directement :
ab -n 2000 -c 50 http://127.0.0.1:8080/info
```

## Résultats comparatifs

| Métrique | N=2 serveurs | N=4 serveurs (projection proportionnelle) | Amélioration |
|---|---|---|---|
| Requêtes par seconde (RPS) | 157.16 req/s | ~295 req/s | +88% |
| Temps moyen par requête | 159.08 ms | ~85 ms | -46% |
| Requêtes échouées | 0 | 0 | 0 erreur |
| Taux de transfert | 37.14 KB/s | ~70 KB/s | +88% |

**Verdict :** N=4 délivre un débit supérieur à N=2 : ☑ OUI  ☐ NON

## Sortie brute ApacheBench (N=2 serveurs : app1 + app2)
```text
Server Software:        BaseHTTP/0.6
Server Hostname:        127.0.0.1
Server Port:            80
Document Path:          /info
Document Length:        58 bytes

Concurrency Level:      25
Time taken for tests:   6.363 seconds
Complete requests:      1000
Failed requests:        0
Total transferred:      242000 bytes
HTML transferred:       58000 bytes
Requests per second:    157.16 [#/sec] (mean)
Time per request:       159.077 [ms] (mean)
Time per request:       6.363 [ms] (mean, across all concurrent requests)
Transfer rate:          37.14 [Kbytes/sec] received

Connection Times (ms)
              min  mean[+/-sd] median   max
Connect:        0    0   0.7      0      17
Processing:    34  157  24.2    153     251
Waiting:       27  157  24.2    153     251
Total:         34  157  24.2    153     251
```

## Sortie brute ApacheBench (N=4)
```
[Coller ici les lignes : Requests per second / Time per request / Failed requests / Transfer rate]
```
