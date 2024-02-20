# frozen_string_literal: true

require_relative '../../../puppet_x/griggi/awssm'

Puppet::Functions.create_function(:'awssm::lookup', Puppet::Functions::InternalFunction) do
  dispatch :lookup do
    cache_param # Completely undocumented feature that I can only find implemented in a single official Puppet module? Sure why not let's try it
    param 'String', :id
    optional_param 'String', :version
    optional_param 'Optional[String]', :region
    optional_param 'Optional[Number]', :cache_stale
    optional_param 'Optional[Boolean]', :ignore_cache
    return_type 'Sensitive'
  end

  # Allows for passing a hash of options to the vault_lookup::lookup() function.
  #
  # @example
  #  $foo = awssm::lookup('secret/some/path/foo',
  #    {'region' => 'us-east-1', 'version' => 'AWSPREVIOUS'}
  #  )
  #
  dispatch :lookup_opts_hash do
    cache_param
    param 'String[1]', :id
    param 'Hash[String[1], Data]', :options
    return_type 'Sensitive'
  end

  # Lookup with a path and an options hash.
  def lookup_opts_hash(cache, id, options = { region => 'us-east-2',
                                              cache_stale => 30,
                                              ignore_cache => false })
    # NOTE: The order of these options MUST be the same as the lookup()
    # function's signature. If new parameters are added to lookup(), or if the
    # order of existing parameters change, those changes must also be made
    # here.
    PuppetX::GRiggi::AWSSM::Lookup.lookup(cache: cache,
                                          id: id,
                                          version: options['version'],
                                          region: options['region'],
                                          cache_stale: options['cache_stale'],
                                          ignore_cache: options['ignore_cache'])
  end

  # Lookup with a path and positional arguments.
  # NOTE: If new parameters are added, or if the order of existing parameters
  # change, those changes must also be made to the lookup() call in
  # lookup_opts_hash().
  def lookup(cache,
             id,
             version = nil,
             region = 'us-east-2',
             cache_stale = '30',
             ignore_cache = false)

    PuppetX::GRiggi::AWSSM::Lookup.lookup(cache: cache,
                                          id: id,
                                          version: version,
                                          region: region,
                                          cache_stale: cache_stale,
                                          ignore_cache: ignore_cache)
  end
end
