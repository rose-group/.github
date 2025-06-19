# Open PGP / GPG private key preparation

## Used software

For this tutorial I used `GnuPG` on `Mac OS`, but GnuPG on other system should be ok, too.
If you have special requirements on a different operating system or different software,
please create issues or PR with clarification.

```shell
gpg --version

gpg (GnuPG) 2.4.7
libgcrypt 1.11.0
Copyright (C) 2024 g10 Code GmbH
License GNU GPL-3.0-or-later <https://gnu.org/licenses/gpl.html>
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
```

## Creating a new private key

You can skip this point if you already have a private key.

Please run and follow instructions

```shell
gpg --full-gen-key
```

Now you can see your keys

```shell
gpg --list-secret-keys --keyid-format long
```

output should be similar to

```shell
------------------------------------------------
sec   rsa4096/0C5CEA1C96038404 2020-12-23 [SC]
      92BBFA4603B33BC283068CA40C5CEA1C96038404
uid                 [ultimate] Test Key <test@example.com>
ssb   rsa4096/3368CCB87F3FC7AE 2020-12-23 [E]

```

We have private key `sec` with keyId `0C5CEA1C96038404`, key has fingerprint `92BBFA4603B33BC283068CA40C5CEA1C96038404`

## Exporting private master key

For signing we need only key with flag `[S]`, so we export only one specific key
(exclamation after `keyId` is important)

```shell
gpg --armor --export-secret-keys 0C5CEA1C96038404!
```

output of this command you can store in github action `GPG_SECRET_KEY` secret or set as `GPG_SECRET_KEY` environment
variable.

## Publishing public key

Finally, you should publish your master public key to a keys server network
in order to make it possible to verify your signatures by others.

eg:

```shell
gpg --keyserver keyserver.ubuntu.com --send-key 0C5CEA1C96038404
```

