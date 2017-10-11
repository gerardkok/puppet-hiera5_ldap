Puppet::Functions.create_function(:ldap_lookup_key) do

  begin
    require 'ldap'
  rescue
    raise Puppet::DataBinding::LookupError, "Must install jruby-ldap gem to use hiera5_ldap"
  end

  dispatch :ldapsearch_lookup_key do
    param 'String[1]', :key
    param 'Hash[String[1],Any]', :options
    param 'Puppet::LookupContext', :context
  end

  PREFIX = 'ldap:///'

  def ldapsearch_lookup_key(key, options, context)
    if context.cache_has_key(key)
      context.cached_value(key)
    else
      result = direct?(key) ? direct_search(key, options, context) : indirect_search(key, options, context)
      context.cache(key, result)
    end
  end

  def direct_search(key, options, context)
    base, scope, filter, attrs = parse(key)

    conn = connection(options, context)

    method = method(options['bind_method'])

    begin
      search(conn, options['bind_dn'], options['bind_password'], method, base, scope, filter, attrs)
    rescue Exception => e
      raise Puppet::DataBinding::LookupError, "Error '#{e}' in ldap_lookup_key(#{key})"
    end
  end

  def indirect_search(key, options, context)
    raw_data = raw_data(options, context)
    context.not_found unless raw_data.include?(key)
    ldapsearch_lookup_key(context.interpolate(raw_data[key]), options, context)
  end

  def connection(options, context)
    if context.cache_has_key(PREFIX)
      context.cached_value(PREFIX)
    else
      conn = options['use_ssl'] ? LDAP::SSLConn.new(options['host'], options['port']) : LDAP::Conn.new(options['host'], options['port'])
      conn.tap { |c| c.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3) }
      context.cache(PREFIX, conn)
    end
  end

  def search(conn, bind_dn, bind_password, bind_method, base_dn, scope, filter, attrs)
    r = []
    conn.bind(bind_dn, bind_password, bind_method) do |b|
      b.search(base_dn, scope, filter, attrs) do |v|
        r << to_hash(v)
      end
    end
    r
  end

  def to_hash(entry)
    entry.attrs.each_with_object({ 'dn' => entry.dn }) { |e, memo| memo[e] = entry[e] }
  end

  def direct?(key)
    key.is_a?(String) && key.start_with?(PREFIX)
  end

  def parse(key)
    base, attrs, scope, filter = key.split(PREFIX).last.split('?')

    return base, scope(scope), filter(filter), attrs(attrs)
  end

  def filter(f)
    f.to_s.empty? ? "objectClass=*" : f
  end

  def attrs(a)
    a.to_s.split(',').map(&:strip)
  end

  def scope(s)
    case s.to_s
    when '', 'sub'
      LDAP::LDAP_SCOPE_SUBTREE
    when 'one'
      LDAP::LDAP_SCOPE_ONELEVEL
    when 'base'
      LDAP::LDAP_SCOPE_BASE
    else
      raise Puppet::DataBinding::LookupError, "ldap_lookup_key: invalid scope '#{s}'"
    end
  end

  def method(m)
    case m.to_s
    when '', 'simple'
      LDAP::LDAP_AUTH_SIMPLE
    when 'none'
      LDAP::LDAP_AUTH_NONE
    when 'sasl'
      LDAP::LDAP_AUTH_SASL
    else
      raise Puppet::DataBinding::LookupError, "ldap_lookup_key: invalid bind_method '#{m}'"
    end
  end

  # this way of using file caching has been taken from
  # https://github.com/puppetlabs/puppet/blob/master/lib/puppet/functions/eyaml_lookup_key.rb
  def raw_data(options, context)
    # nil key is used to indicate that the cache contains the raw content of
    # the eyaml file
    raw_data = context.cached_value(nil)
    if raw_data.nil?
      if options.include?('path')
        raw_data = load_data_hash(options['path'], context)
        context.cache(nil, raw_data)
      else
        raise ArgumentError,
        "'ldap_lookup_key': one of 'path', 'paths' 'glob', 'globs' or 'mapped_paths' must be declared in hiera.yaml when using this lookup_key function"
      end
    end
    raw_data
  end

  def load_data_hash(path, context)
    context.cached_file_data(path) do |content|
      begin
        data = YAML.load(content, path)
        if data.is_a?(Hash)
          Puppet::Pops::Lookup::HieraConfig.symkeys_to_string(data)
        else
          Puppet.warning("#{path}: file does not contain a valid yaml hash")
          {}
        end
      rescue YAML::SyntaxError => ex
        # Psych errors includes the absolute path to the file, so no need to add
        # that to the message
        raise Puppet::DataBinding::LookupError, "Unable to parse #{ex.message}"
      end
    end
  end
end
