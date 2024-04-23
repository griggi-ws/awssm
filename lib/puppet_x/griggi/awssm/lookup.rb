# frozen_string_literal: true

# Taking out of puppet's Vault book
require 'puppet'
begin
  require 'aws-sdk-secretsmanager'
rescue LoadError
  raise Puppet::DataBinding::LookupError, '[AWSSM]: Must install aws-sdk-secretsmanager gem on both agent and server ruby versions to use awssm_lookup'
end
module PuppetX
  module GRiggi
    module AWSSM
      # First module for AWSSM, to lookup a given key (and optionally version)
      class Lookup
        def self.lookup(cache:, id:, region: 'us-east-2', version: nil, cache_stale: 30, ignore_cache: false, create_options: {})
          Puppet.debug '[AWSSM]: Lookup function started'
          cache_key = [id, version, region]
          cache_hash = cache.retrieve(self)
          cached_result = cache_hash[cache_key] unless ignore_cache
          cache_use = false
          if cached_result
            # ! Not currently working as expected
            if (cached_result['date'] <=> Time.now - (cache_stale * 60)) == 1
              Puppet.debug '[AWSSM]: Returning cached value that is still fresh'
              cache_use = true
              return cached_result['data']
            end
            Puppet.debug '[AWSSM]: Cached value is stale, fetching new one'
          end
          result = get_secret(id: id,
                              version: version,
                              region: region,
                              create_options: create_options)
          Puppet.debug '[AWSSM]: Sensitive secret returned.'
          to_cache = {
            data: result,
            date: Time.now
          }
          if cache_use
            cache_hash[cache_key] = to_cache
            Puppet.debug '[AWSSM]: New value stored in cache'
          end
          Puppet.info "[AWSSM]: Successfully looked up value of #{id}"
          result
        end

        def self.create_secret(id:, region:, options: {})
          Puppet.debug '[AWSSM]: create_secret function started'
          secret = nil
          response = nil
          awssm = Aws::SecretsManager::Client.new({
                                                    region: region
                                                  })
          begin
            secret = awssm.get_random_password({
                                                 password_length: options[:password_length] || 32,
                                                 exclude_characters: options[:exclude_characters] || '\'";\\{}',
                                                 exclude_numbers: options[:exclude_numbers] || false,
                                                 exclude_punctuation: options[:exclude_punctuation] || false,
                                                 exclude_uppercase: options[:exclude_uppercase] || false,
                                                 exclude_lowercase: options[:exclude_lowercase] || false,
                                                 include_space: options[:include_space] || false,
                                                 require_each_included_type: options[:require_each_included_type] || true,
                                               }).random_password
            response = awssm.create_secret({
                                             description: options[:description] || 'Created by Puppet',
                                             name:        options[:name] || id,
                                             secret_string: secret,
                                           })
          rescue Aws::SecretsManager::Errors::ServiceError => e
            raise Puppet::Error, "[AWSSM]: Non-specific error #{e} when creating"
          end
          if response.nil?
            raise Puppet::Error, '[AWSSM]: Invalid response when creating'
          end
          secret
        end

        def self.get_secret(id:, version:, region:, create_options:)
          Puppet.debug '[AWSSM]: get_secret function started'
          secret = nil
          response = nil
          awssm = Aws::SecretsManager::Client.new({
                                                    region: region
                                                  })
          begin
            response = awssm.get_secret_value({
                                                secret_id: id,
                                                version_id: version
                                              })
          rescue Aws::SecretsManager::Errors::ResourceNotFoundException
            raise Puppet::Error, "[AWSSM]: No matching key #{id} + version #{version} found, and creating a missing secret is not enabled." unless create_options[:create_missing]
            return create_secret(id, region, create_options)
          rescue Aws::SecretsManager::Errors::ServiceError => e
            raise Puppet::Error, "[AWSSM]: Non-specific error when looking up #{id}: #{e.message}"
          end
          unless response.nil?
            response = response.to_h
            Puppet.debug '[AWSSM]: Response received.'
            secret = if response[:secret_string]
                       response[:secret_string]
                     else
                       response[:secret_binary]
                     end
          end
          Puppet.debug '[AWSSM]: Returning secret as sensitive.'
          Puppet::Pops::Types::PSensitiveType::Sensitive.new(secret)
        end
      end
    end
  end
end
