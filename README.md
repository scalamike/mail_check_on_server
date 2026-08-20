Usage

Check a single domain in short format:
```
./mail_dns.sh domain.com short
```
Check a single domain with full details:
```
./mail_dns.sh domain.com full
```

Check All Locally Routed Domains

To check all domains listed in /etc/localdomains using the short format:
```
for i in $(cat /etc/localdomains); do ./mail_dns.sh $i short; done
```
This checks all domains on the server that are configured to use local mail routing.
