# Landing services

Shared infrastructure for the static landing sites:

- a minimal Python service that validates form requests and sends them through
  Gmail SMTP;
- deployment scripts that publish the landing sites from clean GitHub
  checkouts.

## Form service

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

## Landing deployment

The static deployment tools live in [`deployment/`](deployment/README.md). They
do not use or modify the Docker-oriented `deploy.sh` files in other projects.

On the server:

```bash
sudo ./deployment/deploy-landings.sh ngopie
sudo ./deployment/deploy-landings.sh sns
```
