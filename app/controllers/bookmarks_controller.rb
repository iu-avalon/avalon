# Copyright 2011-2015, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
# 
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed 
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the 
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

class BookmarksController < CatalogController
  include Blacklight::Bookmarks

  self.document_actions.delete( :email )
  self.document_actions.delete( :citation )

  self.add_document_action( :update_access_control, callback: :access_control_action )
  self.add_document_action( :move, callback: :move_action )
  self.add_document_action( :publish, callback: :status_action, tool_partial: 'formless_document_action')
  self.add_document_action( :unpublish, callback: :status_action, tool_partial: 'formless_document_action' )
  self.add_document_action( :delete, callback: :delete_action )

  before_filter :verify_permissions, only: :index

  def verify_permissions
    @response, @documents = action_documents
    mos = @documents.collect { |doc| MediaObject.find( doc.id ) }
    @user_actions = self.document_actions.clone
    @user_actions.delete( :delete ) if mos.any? { |mo| cannot? :destroy, mo }
    @user_actions.delete( :unpublish ) if mos.any? { |mo| cannot? :unpublish, mo }
    if mos.any? { |mo| cannot? :update, mo }
      @user_actions.delete( :publish )
      @user_actions.delete( :move )
    end
    @user_actions.delete( :update_access_control ) if mos.any? { |mo| cannot? :update_access_control, mo }
  end

  def index
    @bookmarks = token_or_current_or_guest_user.bookmarks
    bookmark_ids = @bookmarks.collect { |b| b.document_id.to_s }
  
    @response, @document_list = get_solr_response_for_document_ids(bookmark_ids, defType: 'edismax')

    respond_to do |format|
      format.html { }
      format.rss  { render :layout => false }
      format.atom { render :layout => false }
      format.json do
        render json: render_search_results_as_json
      end

      additional_response_formats(format)
      document_export_formats(format)
    end
  end

  def action_documents
    bookmarks = token_or_current_or_guest_user.bookmarks
    bookmark_ids = bookmarks.collect { |b| b.document_id.to_s }
    get_solr_response_for_document_ids(bookmark_ids, rows: bookmark_ids.count, defType: 'edismax')
  end

  def access_control_action documents
    errors = []
    success_ids = []
    Array(documents.map(&:id)).each do |id|
      media_object = MediaObject.find(id)
      if cannot? :update_access_control, media_object
        errors += ["#{media_object.title} (#{id}) #{t('blacklight.messages.permission_denied')}."]
      else
        success_ids << id
      end
    end
    flash[:success] = t("blacklight.update_access_control.success", count: success_ids.count) if success_ids.count > 0
    flash[:alert] = "#{t('blacklight.update_access_control.alert', count: errors.count)}</br> #{ errors.join('<br/> ') }".html_safe if errors.count > 0

    params[:hidden] = params[:hidden] == "true" if params[:hidden].present?
    MediaObject.access_control_bulk success_ids, params
  end

  def status_action documents
    errors = []
    success_ids = []
    status = params['action']
    Array(documents.map(&:id)).each do |id|
      media_object = MediaObject.find(id)
      if cannot? :update, media_object
        errors += ["#{media_object.title} (#{id}) #{t('blacklight.messages.permission_denied')}."]
      else
        case status
        when 'publish'
          success_ids << id
        when 'unpublish'
          if can? :unpublish, media_object
            success_ids << id
          else
            errors += ["#{media_object.title} (#{id}) #{t('blacklight.messages.permission_denied')}."]
          end
        end
      end
    end
    flash[:success] = t("blacklight.status.success", count: success_ids.count, status: status) if success_ids.count > 0
    flash[:alert] = "#{t('blacklight.status.alert', count: errors.count, status: status)}</br> #{ errors.join('<br/> ') }".html_safe if errors.count > 0
    MediaObject.update_status_bulk success_ids, current_user.user_key, params
  end

  def delete_action documents
    errors = []
    success_ids = []
    Array(documents.map(&:id)).each do |id|
      media_object = MediaObject.find(id)
      if can? :destroy, media_object
        success_ids << id
      else
        errors += ["#{media_object.title} (#{id}) #{t('blacklight.messages.permission_denied')}."]
      end
    end
    flash[:success] = t("blacklight.delete.success", count: success_ids.count) if success_ids.count > 0
    flash[:alert] = "#{t('blacklight.delete.alert', count: errors.count)}</br> #{ errors.join('<br/> ') }".html_safe if errors.count > 0
    MediaObject.delete_bulk success_ids, params
  end

  def move_action documents
    collection = Admin::Collection.find( params[:target_collection_id] )
    if cannot? :read, collection
      flash[:error] =  t("blacklight.move.error", collection_name: collection.name)
    else
      errors = []
      success_ids = []
      Array(documents.map(&:id)).each do |id|
        media_object = MediaObject.find(id)
        if cannot? :update, media_object
          errors += ["#{media_object.title} (#{id}) #{t('blacklight.messages.permission_denied')}."]
        else
          success_ids << id
        end
      end    
      flash[:success] = t("blacklight.move.success", count: success_ids.count, collection_name: collection.name) if success_ids.count > 0
      flash[:alert] = "#{t('blacklight.move.alert', count: errors.count)}</br> #{ errors.join('<br/> ') }".html_safe if errors.count > 0
      MediaObject.move_bulk success_ids, params
    end
  end
end
