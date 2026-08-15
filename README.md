# Landing forms service

A minimal standard-library Python service that validates landing form requests
and sends them through Gmail SMTP.

The production environment file is `/etc/landing-forms.env`. It must be owned
by `root:root` with mode `600`; never commit the Google app password.

Endpoints:

- `GET /health`
- `POST /api/forms`

Apache proxies the public `/api/forms` path to `127.0.0.1:3001`.

Install from the copied server directory:

```bash
sudo ./setup-server.sh
```

The setup prompts for the Google app password without echoing it. Spaces in
Google's displayed 16-character password are removed before it is stored.
