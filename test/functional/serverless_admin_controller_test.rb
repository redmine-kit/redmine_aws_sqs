# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAwsSqs
  # The shared Serverless menu, with only this plugin installed.
  class ServerlessAdminControllerTest < Redmine::ControllerTest
    tests ServerlessAdminController

    def test_the_menu_item_opens_the_jobs_tab
      @request.session[:user_id] = 1
      get :index

      assert_redirected_to '/admin/aws/jobs'
    end

    def test_one_menu_item
      assert_equal(1, Redmine::MenuManager.items(:admin_menu).children.count { |item| item.name == :serverless })
    end

    def test_non_administrators_are_refused
      @request.session[:user_id] = 2
      get :index

      assert_response :forbidden
    end
  end
end
