# Introduction

## Intro

**Purman** is a simple tool created for monitoring docker containers.
It actively monitors your containers for container's status and stats,
and dumps it to the local **sqlite** database.

- It logs the container crash info, crashed container's logs and
  current container status.

- It also logs the system usage of your containers. Stats such as
  `mem_usage`, `cpu_usage`, etc are logged.

- It provides you with helper library to interact with the data dumped
  into the database.

- It provides a web dashboard to look at all the details regarding your
  containers.

## Why use Purman?

### Extensibility

While dumping container's status and stats data to a database might not
be a trivial task. **Purman** tries to do it in the most extendible way.
Purman is purely written in bash, which is very easily modifiable.

You can extend over `purman` easily within your local system. You can
use [purman-db](docs/reference/purman-db) which is a bash library that
is pre-installed with `purman` and exposes all the helper methods for
database and logging and such.

For examples regarding extending it, you can look at [Examples](docs/examples).

### Web dashboard

Purman also includes a fully functional minimalist web-dashboard
which you can run through `purman-dash`. You're able to view your
container's status, it's crashed logs. It's live memory usage, it's
system usage stats and so much more.

For more info regarding `purman-dash`, you can look at [Purman Dashboard](docs/dashboard).
