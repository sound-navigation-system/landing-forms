# Static landing deployment

These scripts are independent from the application/Docker `deploy.sh` files.
They only publish static landing files from a clean GitHub checkout.

## Deploy

From the `landing-forms` checkout on the server:

```bash
sudo ./deployment/deploy-landings.sh ngopie
sudo ./deployment/deploy-landings.sh sns
sudo ./deployment/deploy-landings.sh all
```

The deployer:

1. clones the configured Git branch into a temporary directory;
2. requires an `index.html` and at least two files;
3. saves the current `public_html` as
   `/var/www/<site>/public_html-backup-<site>-DD-MM-YYYY.zip` (another deploy on
   the same day replaces that day's backup);
4. synchronizes the selected source directory into its web root;
5. sets directories to `755`, files to `644`, and ownership to `www-data`;
6. compares source and destination file counts and contents;
7. requests the home page plus configured CSS, JavaScript, and image URLs.

Any failed step stops the command with a non-zero exit code and reports the
failed verification. The `ngopie` entry publishes only to
`/var/www/ngopie.com.ua/public_html`; it does not modify the temporary copy at
`edvin.info`.
