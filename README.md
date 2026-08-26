Usage

Check a single domain in short format:
```
./mail_dns.sh domain.com short
```
Check a single domain with full details:
```
./mail_dns.sh domain.com full
```

To check all locally routed domains with full details:

```
./mail_dns.sh alldomains full
./mail_dns.sh alldomains short
```

This checks all domains on the server that are configured to use local mail routing through /etc/localdomains.

The alldomains option uses the same DKIM, SPF, and MX validation logic as a single-domain check, but automatically runs it against every locally routed domain.
