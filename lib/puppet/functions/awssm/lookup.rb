# frozen_string_literal: true

require_relative '../../../puppet_x/griggi/awssm/lookup'

Puppet::Functions.create_function(:'awssm::lookup', Puppet::Functions::InternalFunction) do
  dispatch :lookup do
    cache_param # Completely undocumented feature that I can only find implemented in a single official Puppet module? Sure why not let's try it
    param 'String', :id
    optional_param 'String', :version
    optional_param 'Optional[String]', :region
    optional_param 'Optional[Number]', :cache_stale
    optional_param 'Optional[Boolean]', :ignore_cache
    optional_param 'Optional[Hash]', :create_options
    return_type 'Sensitive'
  end

  # Allows for passing a hash of options to the vault_lookup::lookup() function.
  #
  # @example
  #  $foo = awssm::lookup('secret/some/path/foo',
  #    { 'version' => 'AWSPREVIOUS', 'region' => 'us-east-1' }
  #  )
  #
  dispatch :lookup_opts_hash do
    cache_param
    param 'String[1]', :id
    param 'Hash[String[1], Data]', :options
    return_type 'Sensitive'
  end

  # Lookup with a path and an options hash.
  def lookup_opts_hash(cache, id, options = { region: 'us-east-2',
                                              version: 'AWSCURRENT',
                                              cache_stale: 30,
                                              ignore_cache: false,
                                              create_options: {
                                                create_missing: true,
                                                password_length: 32,
                                                exclude_characters: '\'";\\{}',
                                                exclude_numbers: false,
                                                exclude_punctuation: false,
                                                exclude_uppercase: false,
                                                exclude_lowercase: false,
                                                include_space: false,
                                                require_each_included_type: true
                                              }, })
    # NOTE: The order of these options MUST be the same as the lookup()
    # function's signature. If new parameters are added to lookup(), or if the
    # order of existing parameters change, those changes must also be made
    # here.
    PuppetX::GRiggi::AWSSM::Lookup.lookup(cache: cache,
                                          id: id,
                                          region: options['region'],
                                          version: options['version'],
                                          cache_stale: options['cache_stale'],
                                          ignore_cache: options['ignore_cache'],
                                          create_options: options['create_options'])
  end

  # Lookup with a path and positional arguments.
  # NOTE: If new parameters are added, or if the order of existing parameters
  # change, those changes must also be made to the lookup() call in
  # lookup_opts_hash().
  def lookup(cache,
             id,
             region = 'us-east-2',
             version = nil,
             cache_stale = 30,
             ignore_cache = false,
             create_options = {
               create_missing: true,
               password_length: 32,
               exclude_characters: '\'";\\{}',
               exclude_numbers: false,
               exclude_punctuation: false,
               exclude_uppercase: false,
               exclude_lowercase: false,
               include_space: false,
               require_each_included_type: true
             })
    Puppet.info '[AWSSM]: Calling lookup function'

    PuppetX::GRiggi::AWSSM::Lookup.lookup(cache: cache,
                                          id: id,
                                          region: region,
                                          version: version,
                                          cache_stale: cache_stale,
                                          ignore_cache: ignore_cache,
                                          create_options: create_options)
  end
end
