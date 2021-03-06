require 'uri'

module LtiProvider
  class Launch < ActiveRecord::Base
    validates :canvas_url, :provider_params, :nonce, presence: true

    attr_accessor :lti_errormsg

    serialize :provider_params

    def self.initialize_from_request(provider, request)
      launch = new

      launch.validate_provider(provider, request)

      launch.provider_params = provider.to_params
      launch.canvas_url      = launch.api_endpoint(provider)
      launch.nonce           = launch.provider_params['oauth_nonce']

      launch
    end

    def self.xml_config(lti_launch_url)
      tc = IMS::LTI::Services::ToolConfig.new(
        'title'         => LtiProvider::XmlConfig.tool_title, # I18n.t('SIS Grade Posting'),
        'description'   => LtiProvider::XmlConfig.tool_description, # I18n.t('Provides grade posting to Student Information Systems through SIS App'),
        'launch_url'    => lti_launch_url,
        'custom_params' => {
          'account_id'       => '$Canvas.account.id',
          'common_css_url'   => '$Canvas.css.common',
          'course_id'        => '$Canvas.course.id',
          'user_id'          => '$Canvas.user.id',
          'api_url'          => '$Canvas.api.baseUrl',
          'high_contrast'    => '$Canvas.user.prefersHighContrast',
        }
      )



      # tc = IMS::LTI::ToolConfig.new({
      #   launch_url: lti_launch_url,
      #   title: LtiProvider::XmlConfig.tool_title,
      #   description: LtiProvider::XmlConfig.tool_description,
      #   custom_params: {
      #     common_css_url: '$Canvas.css.common'
      #   }
      # })

      # tc.extend IMS::LTI::Extensions::Canvas::ToolConfig
      # platform = IMS::LTI::Extensions::Canvas::ToolConfig::PLATFORM

      privacy_level = LtiProvider::XmlConfig.privacy_level || "public"
      tc.send("canvas_privacy_#{privacy_level}!")

      if LtiProvider::XmlConfig.tool_id
        tc.set_ext_param(platform, :tool_id, LtiProvider::XmlConfig.tool_id)
      end

      if LtiProvider::XmlConfig.course_navigation
        tc.canvas_course_navigation!(LtiProvider::XmlConfig.course_navigation.symbolize_keys)
      end

      if LtiProvider::XmlConfig.account_navigation
        tc.canvas_account_navigation!(LtiProvider::XmlConfig.account_navigation.symbolize_keys)
      end

      if LtiProvider::XmlConfig.user_navigation
        tc.canvas_user_navigation!(LtiProvider::XmlConfig.user_navigation.symbolize_keys)
      end

      if LtiProvider::XmlConfig.environments
        tc.set_ext_param(platform, :environments, LtiProvider::XmlConfig.environments.symbolize_keys)
      end

      tc.to_xml(:indent => 2)
    end

    {
      'context_label'                  => :course_name,
      'custom_canvas_account_id'       => :account_id,
      'custom_canvas_course_id'        => :course_id,
      'custom_canvas_user_id'          => :user_id,
      'lis_person_name_full'           => :user_name,
      'ext_roles'                      => :user_roles,
      'tool_consumer_instance_guid'    => :tool_consumer_instance_guid,
      'user_image'                     => :user_avatar_url,
      'custom_common_css_url'          => :common_css_url
    }.each do |provider_param, method_name|
      define_method(method_name) { provider_params[provider_param] }
    end

    def valid_provider?
      !!@valid_provider
    end

    def validate_provider(provider, request)
      self.lti_errormsg =
        if provider.consumer_key.blank?
          "Consumer key not provided."
        elsif provider.consumer_secret.blank?
          "Consumer secret not configured on provider."
        elsif !provider.valid_request?(request)
          "The OAuth signature was invalid."
        elsif oauth_timestamp_too_old?(provider.request_oauth_timestamp)
          "Your request is too old."
        end

      @valid_provider = self.lti_errormsg.blank?
    end

    def api_endpoint(provider)
      if provider.launch_presentation_return_url
        uri = URI.parse(provider.launch_presentation_return_url)
        domain = "#{uri.scheme}://#{uri.host}"
        domain += ":#{uri.port}" unless uri.port.nil? || [80, 443].include?(uri.port.to_i)
        return domain
      end
    end

    private
    def oauth_timestamp_too_old?(timestamp)
      Time.now.utc.to_i - timestamp.to_i > 1.hour.to_i
    end
  end
end
