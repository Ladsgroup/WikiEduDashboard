# frozen_string_literal: true
#= Helpers for campaigns views
module CampaignHelper
  def nav_link(link_text, link_path)
    class_name = current_page?(link_path) ? 'active' : ''

    content_tag(:li, class: 'nav__item', id: "#{params[:action]}-link") do
      content_tag(:p) do
        link_to(link_text, link_path, class: class_name)
      end
    end
  end
end
