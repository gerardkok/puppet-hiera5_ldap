# hiera5_ldap

#### Table of Contents

1. [Description](#description)
1. [Setup](#setup)
    * [What hiera5_ldap affects](#what-hiera5_ldap-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with hiera5_ldap](#beginning-with-hiera5_ldap)
1. [Usage](#usage)
1. [Reference](#reference)
1. [Limitations](#limitations)
1. [Development](#development)

## Description

This is a custom Hiera 5 backend, that allows hiera to perform LDAP queries. It is intended to be used in a puppet environment with a puppet master; it (likely) won't work in a masterless puppet environment.

## Setup

### What hiera5_ldap affects

This backend only reads from LDAP, and does not need write access.

### Setup Requirements

This backend leverages the [jruby-ldap](https://rubygems.org/gems/jruby-ldap) ruby gem. This gem needs to be installed on your puppet master:
```bash
$ /opt/puppetlabs/bin/puppetserver gem install jruby-ldap
```
You'll also need read access to the LDAP instance you want to query from your puppet master.

### Beginning with hiera5_ldap

To be able to query your LDAP instance from hiera, you'll have to configure how to connect to your LDAP instance, in your hiera hierarchy, i.e. in your `hiera.yaml` file. The minimum configuration would be:
~~~
...
hierarchy:
  ...
  - name: "Hiera-LDAP lookup"
    lookup_key: ldap_lookup_key
    options:
      host: '<your LDAP instance>'
  ...
~~~
In order to perform LDAP searches, hiera would connect to `<your LDAP instance>`, using simple binding without username and password, without using SSL, on the default port 389.

In your puppet code, you can now query your LDAP instance with a hiera call:
```puppet
hiera('ldap:///<LDAP search>')
```
where `LDAP search` is formatted like an [LDAP URL](https://www.ldap.com/ldap-urls), like so: `<base DN>?<attributes>?<scope>?<filter>`.

The result will be an array of hashes, with the LDAP attributes as keys. The value of a hash key, or attribute, is an array of values found in LDAP. The exception is the value of attribute 'dn', which is a string instead of an array.

For example, if your groups are 'posixGroups' in the 'ou=Groups' subtree, you can query the members of the 'admins' group as follows:
```puppet
hiera('ldap:///ou=Groups,dc=example,dc=com?memberUid?sub?(cn=admins)')
```
This results in:
~~~
- dn: 'cn=admins,ou=Groups,dc=example'
  memberUid: ['admin1', 'admin2', 'admin3']
~~~
You have to include the base DN in your query. If you omit the attributes from the query, you'll get all attributes. If you omit the scope, it will default to 'sub', and if you leave out the filter, it will default to 'objectClass=\*'. You can also leave out trailing question marks. I.e., if you do
```puppet
hiera('ldap:///dc=example,dc=com')
```
you'll get your entire LDAP tree as result.

## Usage

The above examples are all 'direct'; the LDAP URL is just a parameter to the heira call. You can also use 'indirect' LDAP queries, where the actual query is looked up in a yaml file, much like regular hiera keys are looked up. This allows for [automatic class parameter lookup](https://docs.puppet.com/puppet/4.9/hiera_automatic.html).

For example, if you configure your `hiera.yaml` like this:
~~~
...
hierarchy:
  ...
  - name: "Hiera-LDAP lookup"
    path: "nodes/%{trusted.certname}.ldap"
    lookup_key: ldap_lookup_key
    options:
      host: '<your LDAP instance>'
  ...
~~~
and the file `nodes/<certname>.ldap` looks like this:
~~~
my_class::users: 'ldap:///ou=People,dc=example,dc=com??sub?uid=*'
~~~
and you `my_class` module looks like this:
```puppet
class my_class(Array[Hash] $users = [])
```
then, when the puppet master prepares the for node `<certname>`, for the value of `users` it will look up the LDAP query in `nodes/<certname>.ldap`, perform the query, and plug the value into the `users` variable.

Indirect queries also support hiera interpolation, so you should be able to write something like:
~~~
my_class::host_aliases: 'ldap:///ou=Hosts,dc=example,dc=com?cn?sub?cn=%{facts.hostname}'
~~~

## Reference

### Hiera hierarchy

#### `path`/`paths`

An array of yaml formatted files in your hiera tree that link variables to LDAP queries. I suppose you can re-use your yaml/eyaml hiera file, but I think you'll need to be sure your `hiera.yaml` contains the LDAP section before yaml or eyaml sections.

#### `options`

##### `host`

The hostname of your LDAP instance. Required.

##### `port`

The port that your LDAP service listens on. Default: 389 when `use_ssl` is false, 636 when `use_ssl` is true.

##### `bind_dn`

The bind DN necessary to query your LDAP instance, for example: `cn=admin,dc=example,dc=com`. Default empty.

##### `bind_password`

The password that goes with your `bind_dn`. Default empty.

##### `bind_method`

The bind method. Available options: `none` (which is `simple`, but with `bind_dn` and `bind_password` ignored), `simple`, `sasl`. Default: `simple`.

##### `use_ssl`

Whether to use SSL. Boolean, default `false`.

If you want to use SSL, you'll have to ensure JRuby can verify your LDAP server certificate. For this, you have to you add a certificate to the Java keystore that verifies your LDAP server certificate. For example, this can be the root certificate of your local CA, or the self-signed certificate of your LDAP server.

On Ubuntu, this can be achieved by putting the certificate in `/usr/local/share/ca-certificates` on your puppet master, and then running `update-ca-certificates`. On other distributions it will probably work similarly, or you can use `keytool` to add the certificate to the `jre/lib/security/cacerts` file in your java distribution. For example:
```
# keytool -storepass changeit -import -noprompt -alias '<certificate name>' -keystore <cacerts> -file '<certificate file>'
```
You cannot use SSL and opt out of verifying the certificate, because that is not supported by `jruby-ldap`.

### LDAP URL

An LDAP URL has the following format: `ldap:///<base DN>?<attributes>?<scope>?<filter>`. The prefix `ldap:///` is fixed.

#### `<base DN>`

The (search) base DN for your LDAP instance, like `ou=People,dc=example,dc=com`. Required.

#### `<attributes>`

A comma separated list of attributes to return. When empty, all attributes are returned. The special attribute 'dn' is always returned. Default: empty.

#### `<scope>`

The scope of the query. Available options: `one` (singleLevel), `base` (baseObject), `sub` (wholeSubtree). Default: `sub`.

#### `<filter>`

LDAP filter to use, follows regular LDAP filter syntax (i.e. you can write complex queries). Default: `objectClass=*`.

## Limitations

This backend uses jruby-ldap instead of [net/ldap](https://rubygems.org/gems/net-ldap), because net/ldap requires Ruby 2.0 support, but that is not yet the default on a puppet 4/5 master. I intend to rewrite this to net/ldap once JRuby on a puppet 4/5 master becomes Ruby 2.0 compatible.

One of the limitations of using jruby-ldap is that absence of StartTLS.

Further limitations:
- no unit tests to speak of (I have currently no idea how to test a custom hiera backend)
- this backend has seen extremely limited real-world testing
- only tested on Ubuntu 16.04.

## Todo

- allow for multiple LDAP servers in `hiera.yaml`
- allow for queries to be written as a hash, i.e. like:
  ~~~
  query:
    base_dn: ou=People,dc=example,dc=com
    attributes: uid
    scope: sub
    filter: (uid=*)
  ~~~

## Development

Run `rake spec` to run the tests (but nothing useful there right now).

## Release Notes

Initial version, treat as a Minimum Viable Product.
