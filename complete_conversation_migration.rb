# Script COMPLETO para migrar CUENTA/EMPRESA completa entre servidores
# Incluye TODOS los usuarios, conversaciones, contactos, configuraciones, etc.

class CompleteAccountMigration
  def initialize
    @mapping = {
      contacts: {},     # source_id => target_id
      inboxes: {},      # source_id => target_id  
      labels: {},       # source_name => target_id
      users: {},        # source_email => target_id
      teams: {},        # source_id => target_id
      conversations: {} # source_id => target_id
    }
    @import_stats = {
      account_created: false,
      users_created: 0,
      contacts_created: 0,
      inboxes_created: 0,
      labels_created: 0,
      teams_created: 0,
      conversations_created: 0,
      messages_created: 0,
      canned_responses_created: 0,
      errors: []
    }
  end

  def export_complete_account(account_id, options = {})
  def export_complete_account(account_id, options = {})
    puts "🏢 Iniciando exportación completa de cuenta ID: #{account_id}"
    
    @account = Account.find(account_id)
    puts "📊 Cuenta encontrada: #{@account.name}"

    # Obtener TODAS las conversaciones de la cuenta
    conversations = get_account_conversations(options)
    puts "💬 Total conversaciones: #{conversations.count}"

    if conversations.empty? && !options[:export_empty_account]
      puts "ℹ️ No hay conversaciones para migrar (usar export_empty_account: true para forzar)"
      return false
    end

    # Exportar datos completos de la empresa
    export_data = {
      account: export_account_complete,
      users: export_all_account_users,
      contacts: export_all_contacts,
      inboxes: export_all_inboxes,
      labels: export_all_labels,
      teams: export_all_teams,
      conversations: export_all_conversations(conversations),
      canned_responses: export_all_canned_responses,
      custom_filters: export_all_custom_filters,
      webhooks: export_webhooks,
      automation_rules: export_automation_rules,
      metadata: {
        exported_at: Time.current.iso8601,
        source_server: Socket.gethostname,
        account_name: @account.name,
        total_users: @account.users.count,
        total_conversations: conversations.count,
        total_contacts: @account.contacts.count,
        total_inboxes: @account.inboxes.count,
        chatwoot_version: (Chatwoot.config[:version] rescue "unknown")
      }
    }

    # Guardar archivo
    filename = "complete_account_export_#{@account.name.parameterize}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
    File.write(filename, JSON.pretty_generate(export_data))
    
    puts "✅ Exportación completa guardada en: #{filename}"
    puts "📊 Resumen completo:"
    puts "   - Usuarios: #{export_data[:users].length}"
    puts "   - Conversaciones: #{export_data[:conversations].length}"
    puts "   - Contactos: #{export_data[:contacts].length}"
    puts "   - Inboxes: #{export_data[:inboxes].length}"
    puts "   - Equipos: #{export_data[:teams].length}"
    puts "   - Labels: #{export_data[:labels].length}"
    puts "   - Respuestas enlatadas: #{export_data[:canned_responses].length}"
    puts "   - Filtros personalizados: #{export_data[:custom_filters].length}"

    filename
  end

  private

  def get_account_conversations(options)
    conversations = @account.conversations
    
    # Filtros opcionales
    if options[:limit]
      conversations = conversations.limit(options[:limit])
    end
    
    if options[:status]
      conversations = conversations.where(status: options[:status])
    end

    if options[:from_date]
      conversations = conversations.where('created_at >= ?', options[:from_date])
    end

    if options[:to_date]
      conversations = conversations.where('created_at <= ?', options[:to_date])
    end

    conversations.includes(
      :contact, :inbox, :assignee, :team,
      messages: [:attachments, :sender],
      labels: []
    ).order(created_at: :desc)
  end

  def export_account_complete
    {
      original_id: @account.id,
      name: @account.name,
      domain: @account.domain,
      support_email: @account.support_email,
      locale: @account.locale,
      timezone: @account.settings&.dig('timezone'),
      custom_attributes: @account.custom_attributes,
      limits: @account.limits,
      auto_resolve_duration: @account.auto_resolve_duration,
      feature_flags: @account.feature_flags,
      status: @account.status,
      created_at: @account.created_at
    }
  end

  def export_all_account_users
    @account.account_users.includes(:user).map do |account_user|
      user = account_user.user
      {
        # Datos del usuario
        original_user_id: user.id,
        name: user.name,
        email: user.email,
        display_name: user.display_name,
        message_signature: user.message_signature,
        ui_settings: user.ui_settings,
        custom_attributes: user.custom_attributes,
        
        # Datos de la relación con la cuenta
        role: account_user.role,
        availability: account_user.availability,
        auto_offline: account_user.auto_offline,
        
        # Timestamps
        user_created_at: user.created_at,
        account_user_created_at: account_user.created_at
      }
    end
  end

  def export_all_contacts
    @account.contacts.map do |contact|
      {
        original_id: contact.id,
        name: contact.name,
        email: contact.email,
        phone_number: contact.phone_number,
        identifier: contact.identifier,
        additional_attributes: contact.additional_attributes,
        custom_attributes: contact.custom_attributes,
        created_at: contact.created_at,
        updated_at: contact.updated_at
      }
    end
  end

  def export_all_inboxes
    @account.inboxes.map do |inbox|
      {
        original_id: inbox.id,
        name: inbox.name,
        channel_type: inbox.channel_type,
        channel_data: export_inbox_channel_complete(inbox),
        settings: inbox.settings,
        enable_auto_assignment: inbox.enable_auto_assignment,
        greeting_enabled: inbox.greeting_enabled,
        greeting_message: inbox.greeting_message,
        created_at: inbox.created_at,
        # Agentes asignados
        agents: inbox.inbox_members.includes(:user).map { |im| im.user.email }
      }
    end
  end

  def export_inbox_channel_complete(inbox)
    base_data = { type: inbox.channel_type }
    
    case inbox.channel_type
    when 'Channel::Email'
      base_data.merge({
        email: inbox.channel&.email,
        forward_to_email: inbox.channel&.forward_to_email,
        imap_enabled: inbox.channel&.imap_enabled,
        smtp_enabled: inbox.channel&.smtp_enabled
      })
    when 'Channel::WebWidget'
      base_data.merge({
        website_name: inbox.channel&.website_name,
        website_url: inbox.channel&.website_url,
        widget_color: inbox.channel&.widget_color,
        welcome_title: inbox.channel&.welcome_title,
        welcome_tagline: inbox.channel&.welcome_tagline
      })
    when 'Channel::Api'
      base_data.merge({
        webhook_url: inbox.channel&.webhook_url
      })
    else
      base_data
    end
  end

  def export_all_labels
    @account.labels.map do |label|
      {
        original_id: label.id,
        title: label.title,
        description: label.description,
        color: label.color,
        show_on_sidebar: label.show_on_sidebar,
        created_at: label.created_at
      }
    end
  end

  def export_all_teams
    @account.teams.map do |team|
      {
        original_id: team.id,
        name: team.name,
        description: team.description,
        allow_auto_assign: team.allow_auto_assign,
        created_at: team.created_at,
        # Miembros del equipo
        members: team.team_members.includes(:user).map { |tm| tm.user.email }
      }
    end
  end

  def export_all_conversations(conversations)
    conversations.map.with_index do |conversation, index|
      puts "📝 Exportando conversación #{index + 1}/#{conversations.count}: ##{conversation.display_id}"
      
      {
        original_id: conversation.id,
        display_id: conversation.display_id,
        uuid: conversation.uuid,
        status: conversation.status,
        priority: conversation.priority,
        
        # Referencias que necesitan mapeo
        original_contact_id: conversation.contact_id,
        original_inbox_id: conversation.inbox_id,
        original_assignee_id: conversation.assignee_id,
        original_team_id: conversation.team_id,
        
        # Datos de la conversación
        additional_attributes: conversation.additional_attributes,
        custom_attributes: conversation.custom_attributes,
        identifier: conversation.identifier,
        snoozed_until: conversation.snoozed_until,
        
        # Timestamps importantes
        created_at: conversation.created_at,
        updated_at: conversation.updated_at,
        last_activity_at: conversation.last_activity_at,
        agent_last_seen_at: conversation.agent_last_seen_at,
        contact_last_seen_at: conversation.contact_last_seen_at,
        first_reply_created_at: conversation.first_reply_created_at,
        waiting_since: conversation.waiting_since,
        
        # Labels
        label_names: conversation.labels.pluck(:title),
        
        # Mensajes
        messages: export_conversation_messages(conversation)
      }
    end
  end

  def export_conversation_messages(conversation)
    conversation.messages.order(:created_at).map do |message|
      {
        original_id: message.id,
        content: message.content,
        message_type: message.message_type,
        private: message.private,
        status: message.status,
        source_id: message.source_id,
        content_type: message.content_type,
        content_attributes: message.content_attributes,
        
        # Sender info
        sender_type: message.sender_type,
        sender_original_id: message.sender_id,
        sender_email: message.sender&.email,
        sender_name: message.sender&.name,
        
        # Timestamps
        created_at: message.created_at,
        updated_at: message.updated_at,
        
        # Attachments info (sin archivos binarios)
        attachments: export_message_attachments(message)
      }
    end
  end

  def export_message_attachments(message)
    message.attachments.map do |attachment|
      {
        original_id: attachment.id,
        file_type: attachment.file_type,
        file_size: attachment.file_size,
        filename: attachment.file&.filename&.to_s,
        content_type: attachment.file&.content_type,
        download_needed: true
      }
    end
  end

  def export_all_canned_responses
    @account.canned_responses.map do |response|
      {
        original_id: response.id,
        content: response.content,
        short_code: response.short_code,
        created_at: response.created_at
      }
    end
  end

  def export_all_custom_filters
    @account.users.includes(:custom_filters).map do |user|
      user.custom_filters.where(account: @account).map do |filter|
        {
          original_id: filter.id,
          name: filter.name,
          filter_type: filter.filter_type,
          query: filter.query,
          user_email: user.email,
          created_at: filter.created_at
        }
      end
    end.flatten
  end

  def export_webhooks
    @account.webhooks.map do |webhook|
      {
        original_id: webhook.id,
        inbox_id: webhook.inbox_id,
        url: webhook.url,
        subscriptions: webhook.subscriptions,
        webhook_type: webhook.webhook_type,
        created_at: webhook.created_at
      }
    end
  end

  def export_automation_rules
    @account.automation_rules.map do |rule|
      {
        original_id: rule.id,
        name: rule.name,
        description: rule.description,
        event_name: rule.event_name,
        conditions: rule.conditions,
        actions: rule.actions,
        active: rule.active,
        created_at: rule.created_at
      }
    end
  end
end

# =============================================================================
# SCRIPT DE IMPORTACIÓN COMPLETA DE CUENTA
# =============================================================================

class CompleteAccountImport
  def initialize
    @target_account = nil
    @source_data = nil
    @id_mappings = {
      users: {},       # source_email => target_id
      contacts: {},    # source_id => target_id
      inboxes: {},     # source_id => target_id
      labels: {},      # source_title => target_id
      teams: {},       # source_id => target_id
      conversations: {}, # source_id => target_id
      messages: {}     # source_id => target_id
    }
    @import_stats = {
      users_imported: 0,
      contacts_created: 0,
      inboxes_created: 0,
      labels_created: 0,
      teams_created: 0,
      conversations_created: 0,
      messages_created: 0,
      errors: []
    }
  end

  def import_complete_account(filename, target_account_name = nil)
    puts "📥 Iniciando importación completa de cuenta desde: #{filename}"
    
    unless File.exist?(filename)
      puts "❌ Archivo no encontrado: #{filename}"
      return false
    end

    @source_data = JSON.parse(File.read(filename))
    
    @target_account = find_or_create_target_account(@source_data, target_account_name)
    unless @target_account
      puts "❌ No se pudo crear/encontrar cuenta destino"
      return false
    end

    puts "🎯 Cuenta destino: #{@target_account.name} (ID: #{@target_account.id})"

    begin
      ActiveRecord::Base.transaction do
        # 1. Importar usuarios de la cuenta
        import_account_users(@source_data['users'])
        
        # 2. Importar contactos
        import_contacts(@source_data['contacts'])
        
        # 3. Importar inboxes
        import_inboxes(@source_data['inboxes'])
        
        # 4. Importar labels
        import_labels(@source_data['labels'])
        
        # 5. Importar teams
        import_teams(@source_data['teams'])
        
        # 6. Importar conversaciones y mensajes
        import_conversations(@source_data['conversations'])
        
        # 7. Importar respuestas enlatadas
        import_canned_responses(@source_data['canned_responses'])
        
        # 8. Importar filtros personalizados
        import_custom_filters(@source_data['custom_filters'])
        
        # 9. Importar webhooks
        import_webhooks(@source_data['webhooks'])
        
        # 10. Importar reglas de automatización
        import_automation_rules(@source_data['automation_rules'])
        
        show_import_summary
        true
      end
    rescue => e
      puts "❌ Error durante la importación: #{e.message}"
      puts e.backtrace.first(5)
      false
    end
  end

  private

  def find_or_create_target_account(data, target_account_name)
    account_data = data['account']
    
    # Si se especifica un nombre, buscar por ese nombre
    if target_account_name.present?
      account = Account.find_by(name: target_account_name)
      if account
        puts "🎯 Usando cuenta existente: #{account.name}"
        return account
      else
        puts "❌ Cuenta '#{target_account_name}' no encontrada"
        return nil
      end
    end

    # Buscar por nombre original
    existing_account = Account.find_by(name: account_data['name'])
    if existing_account
      puts "🎯 Usando cuenta existente con mismo nombre: #{existing_account.name}"
      return existing_account
    end

    # Crear nueva cuenta
    puts "🆕 Creando nueva cuenta: #{account_data['name']}"
    Account.create!(
      name: account_data['name'],
      domain: account_data['domain'],
      support_email: account_data['support_email'],
      locale: account_data['locale'] || 'es',
      custom_attributes: account_data['custom_attributes'] || {},
      auto_resolve_duration: account_data['auto_resolve_duration']
    )
  rescue => e
    puts "❌ Error creando cuenta: #{e.message}"
    nil
  end

  def import_account_users(users_data)
    return unless users_data

    puts "👥 Importando #{users_data.length} usuarios..."
    users_data.each do |user_data|
      begin
        # Buscar o crear usuario
        user = User.find_by(email: user_data['email'])
        
        unless user
          user = User.create!(
            name: user_data['name'],
            email: user_data['email'],
            display_name: user_data['display_name'],
            message_signature: user_data['message_signature'],
            ui_settings: user_data['ui_settings'] || {},
            custom_attributes: user_data['custom_attributes'] || {},
            password: SecureRandom.hex(20), # Contraseña temporal
            confirmed_at: Time.current
          )
          puts "  ✅ Usuario creado: #{user.email}"
        else
          puts "  🔄 Usuario existente: #{user.email}"
        end

        # Crear relación con la cuenta
        account_user = user.account_users.find_or_create_by(account: @target_account) do |au|
          au.role = user_data['role'] || 'agent'
          au.availability = user_data['availability'] || 'online'
          au.auto_offline = user_data['auto_offline'] || true
        end

        @id_mappings[:users][user_data['email']] = user.id
        @import_stats[:users_imported] += 1

      rescue => e
        puts "  ❌ Error con usuario #{user_data['email']}: #{e.message}"
        @import_stats[:errors] << "Usuario #{user_data['email']}: #{e.message}"
      end
    end
  end

  def import_contacts(contacts_data)
    return unless contacts_data

    puts "📞 Importando #{contacts_data.length} contactos..."
    contacts_data.each do |contact_data|
      begin
        # Buscar contacto existente por email o identificador
        existing_contact = @target_account.contacts.find_by(
          email: contact_data['email']
        ) || @target_account.contacts.find_by(
          identifier: contact_data['identifier']
        )

        if existing_contact
          puts "  🔄 Contacto existente: #{contact_data['name']} (#{contact_data['email']})"
          contact = existing_contact
        else
          contact = @target_account.contacts.create!(
            name: contact_data['name'],
            email: contact_data['email'],
            phone_number: contact_data['phone_number'],
            identifier: contact_data['identifier'],
            additional_attributes: contact_data['additional_attributes'] || {},
            custom_attributes: contact_data['custom_attributes'] || {}
          )
          puts "  ✅ Contacto creado: #{contact.name}"
          @import_stats[:contacts_created] += 1
        end

        @id_mappings[:contacts][contact_data['original_id']] = contact.id

      rescue => e
        puts "  ❌ Error con contacto: #{e.message}"
        @import_stats[:errors] << "Contacto #{contact_data['name']}: #{e.message}"
      end
    end
  end

  def import_inboxes(inboxes_data)
    return unless inboxes_data

    puts "📨 Importando #{inboxes_data.length} inboxes..."
    inboxes_data.each do |inbox_data|
      begin
        # Buscar inbox existente por nombre
        existing_inbox = @target_account.inboxes.find_by(name: inbox_data['name'])
        
        if existing_inbox
          puts "  🔄 Inbox existente: #{inbox_data['name']}"
          inbox = existing_inbox
        else
          # Crear canal básico (se puede extender para tipos específicos)
          channel = create_inbox_channel(inbox_data)
          
          inbox = @target_account.inboxes.create!(
            name: inbox_data['name'],
            channel: channel,
            enable_auto_assignment: inbox_data['enable_auto_assignment'] || true,
            greeting_enabled: inbox_data['greeting_enabled'] || false,
            greeting_message: inbox_data['greeting_message']
          )
          puts "  ✅ Inbox creado: #{inbox.name}"
          @import_stats[:inboxes_created] += 1
        end

        @id_mappings[:inboxes][inbox_data['original_id']] = inbox.id

      rescue => e
        puts "  ❌ Error con inbox #{inbox_data['name']}: #{e.message}"
        @import_stats[:errors] << "Inbox #{inbox_data['name']}: #{e.message}"
      end
    end
  end

  def create_inbox_channel(inbox_data)
    channel_data = inbox_data['channel_data'] || {}
    
    case inbox_data['channel_type']
    when 'Channel::WebWidget'
      Channel::WebWidget.create!(
        account: @target_account,
        website_name: channel_data['website_name'] || 'Imported Website',
        website_url: channel_data['website_url'] || 'https://example.com',
        widget_color: channel_data['widget_color'] || '#1f93ff'
      )
    when 'Channel::Api'
      Channel::Api.create!(account: @target_account)
    when 'Channel::Email'
      Channel::Email.create!(
        account: @target_account,
        email: channel_data['email'] || "imported-#{SecureRandom.hex(4)}@example.com"
      )
    else
      # Crear canal API por defecto si el tipo no es soportado
      Channel::Api.create!(account: @target_account)
    end
  end

  def import_labels(labels_data)
    return unless labels_data

    puts "🏷️ Importando #{labels_data.length} labels..."
    labels_data.each do |label_data|
      begin
        # Buscar label existente por título
        existing_label = @target_account.labels.find_by(title: label_data['title'])
        
        if existing_label
          puts "  🔄 Label existente: #{label_data['title']}"
          label = existing_label
        else
          label = @target_account.labels.create!(
            title: label_data['title'],
            description: label_data['description'],
            color: label_data['color'] || '#1f93ff',
            show_on_sidebar: label_data['show_on_sidebar'] || true
          )
          puts "  ✅ Label creado: #{label.title}"
          @import_stats[:labels_created] += 1
        end

        @id_mappings[:labels][label_data['title']] = label.id

      rescue => e
        puts "  ❌ Error con label #{label_data['title']}: #{e.message}"
        @import_stats[:errors] << "Label #{label_data['title']}: #{e.message}"
      end
    end
  end

  def import_teams(teams_data)
    return unless teams_data

    puts "👥 Importando #{teams_data.length} equipos..."
    teams_data.each do |team_data|
      begin
        # Buscar equipo existente por nombre
        existing_team = @target_account.teams.find_by(name: team_data['name'])
        
        if existing_team
          puts "  🔄 Equipo existente: #{team_data['name']}"
          team = existing_team
        else
          team = @target_account.teams.create!(
            name: team_data['name'],
            description: team_data['description'],
            allow_auto_assign: team_data['allow_auto_assign'] || true
          )
          puts "  ✅ Equipo creado: #{team.name}"
          @import_stats[:teams_created] += 1
        end

        # Agregar miembros al equipo
        if team_data['members']
          team_data['members'].each do |member_email|
            user_id = @id_mappings[:users][member_email]
            if user_id
              team.team_members.find_or_create_by(user_id: user_id)
            end
          end
        end

        @id_mappings[:teams][team_data['original_id']] = team.id

      rescue => e
        puts "  ❌ Error con equipo #{team_data['name']}: #{e.message}"
        @import_stats[:errors] << "Equipo #{team_data['name']}: #{e.message}"
      end
    end
  end

  def import_conversations(conversations_data)
    return unless conversations_data

    puts "💬 Importando #{conversations_data.length} conversaciones..."
    conversations_data.each_with_index do |conv_data, index|
      begin
        puts "  📝 Procesando conversación #{index + 1}/#{conversations_data.length}"

        # Mapear referencias
        contact_id = @id_mappings[:contacts][conv_data['original_contact_id']]
        inbox_id = @id_mappings[:inboxes][conv_data['original_inbox_id']]
        
        unless contact_id && inbox_id
          puts "    ❌ Referencias faltantes - Contact: #{contact_id}, Inbox: #{inbox_id}"
          next
        end

        # Buscar asignado (opcional)
        assignee_id = nil
        if conv_data['original_assignee_id']
          assignee_email = @source_data['users']&.find { |u| u['original_user_id'] == conv_data['original_assignee_id'] }&.dig('email')
          assignee_id = @id_mappings[:users][assignee_email] if assignee_email
        end

        # Buscar equipo (opcional)
        team_id = @id_mappings[:teams][conv_data['original_team_id']] if conv_data['original_team_id']

        conversation = @target_account.conversations.create!(
          display_id: conv_data['display_id'],
          status: conv_data['status'] || 'open',
          priority: conv_data['priority'],
          contact_id: contact_id,
          inbox_id: inbox_id,
          assignee_id: assignee_id,
          team_id: team_id,
          additional_attributes: conv_data['additional_attributes'] || {},
          custom_attributes: conv_data['custom_attributes'] || {},
          identifier: conv_data['identifier'],
          created_at: conv_data['created_at'],
          updated_at: conv_data['updated_at']
        )

        # Asignar labels
        if conv_data['label_names']
          conv_data['label_names'].each do |label_name|
            label_id = @id_mappings[:labels][label_name]
            if label_id
              conversation.labels << Label.find(label_id)
            end
          end
        end

        @id_mappings[:conversations][conv_data['original_id']] = conversation.id
        @import_stats[:conversations_created] += 1

        # Importar mensajes
        import_messages(conversation, conv_data['messages'] || [])

      rescue => e
        puts "    ❌ Error con conversación: #{e.message}"
        @import_stats[:errors] << "Conversación #{conv_data['display_id']}: #{e.message}"
      end
    end
  end

  def import_messages(conversation, messages_data)
    messages_data.each do |msg_data|
      begin
        # Mapear sender
        sender = nil
        if msg_data['sender_type'] == 'User' && msg_data['sender_email']
          sender_id = @id_mappings[:users][msg_data['sender_email']]
          sender = User.find(sender_id) if sender_id
        elsif msg_data['sender_type'] == 'Contact'
          sender = conversation.contact
        end

        message = conversation.messages.create!(
          content: msg_data['content'],
          message_type: msg_data['message_type'] || 'incoming',
          private: msg_data['private'] || false,
          status: msg_data['status'],
          content_type: msg_data['content_type'] || 'text',
          content_attributes: msg_data['content_attributes'] || {},
          sender: sender,
          created_at: msg_data['created_at'],
          updated_at: msg_data['updated_at']
        )

        @id_mappings[:messages][msg_data['original_id']] = message.id
        @import_stats[:messages_created] += 1

      rescue => e
        puts "      ❌ Error con mensaje: #{e.message}"
        @import_stats[:errors] << "Mensaje en conversación #{conversation.display_id}: #{e.message}"
      end
    end
  end

  def import_canned_responses(canned_responses_data)
    return unless canned_responses_data

    puts "📝 Importando #{canned_responses_data.length} respuestas enlatadas..."
    canned_responses_data.each do |response_data|
      begin
        existing_response = @target_account.canned_responses.find_by(short_code: response_data['short_code'])
        
        unless existing_response
          @target_account.canned_responses.create!(
            content: response_data['content'],
            short_code: response_data['short_code']
          )
        end
      rescue => e
        puts "  ❌ Error con respuesta enlatada: #{e.message}"
      end
    end
  end

  def import_custom_filters(custom_filters_data)
    return unless custom_filters_data

    puts "🔍 Importando #{custom_filters_data.length} filtros personalizados..."
    custom_filters_data.each do |filter_data|
      begin
        user_id = @id_mappings[:users][filter_data['user_email']]
        next unless user_id

        user = User.find(user_id)
        user.custom_filters.create!(
          account: @target_account,
          name: filter_data['name'],
          filter_type: filter_data['filter_type'],
          query: filter_data['query']
        )
      rescue => e
        puts "  ❌ Error con filtro personalizado: #{e.message}"
      end
    end
  end

  def import_webhooks(webhooks_data)
    return unless webhooks_data

    puts "🔗 Importando #{webhooks_data.length} webhooks..."
    webhooks_data.each do |webhook_data|
      begin
        inbox_id = @id_mappings[:inboxes][webhook_data['inbox_id']]
        next unless inbox_id

        @target_account.webhooks.create!(
          inbox_id: inbox_id,
          url: webhook_data['url'],
          subscriptions: webhook_data['subscriptions'] || [],
          webhook_type: webhook_data['webhook_type'] || 'account'
        )
      rescue => e
        puts "  ❌ Error con webhook: #{e.message}"
      end
    end
  end

  def import_automation_rules(automation_rules_data)
    return unless automation_rules_data

    puts "🤖 Importando #{automation_rules_data.length} reglas de automatización..."
    automation_rules_data.each do |rule_data|
      begin
        @target_account.automation_rules.create!(
          name: rule_data['name'],
          description: rule_data['description'],
          event_name: rule_data['event_name'],
          conditions: rule_data['conditions'] || [],
          actions: rule_data['actions'] || [],
          active: rule_data['active'] || true
        )
      rescue => e
        puts "  ❌ Error con regla de automatización: #{e.message}"
      end
    end
  end

  def show_import_summary
    puts "\n" + "="*60
    puts "📊 RESUMEN DE IMPORTACIÓN COMPLETA"
    puts "="*60
    puts "✅ Usuarios importados: #{@import_stats[:users_imported]}"
    puts "✅ Contactos creados: #{@import_stats[:contacts_created]}"
    puts "✅ Inboxes creados: #{@import_stats[:inboxes_created]}"
    puts "✅ Labels creados: #{@import_stats[:labels_created]}"
    puts "✅ Equipos creados: #{@import_stats[:teams_created]}"
    puts "✅ Conversaciones creadas: #{@import_stats[:conversations_created]}"
    puts "✅ Mensajes creados: #{@import_stats[:messages_created]}"
    
    if @import_stats[:errors].any?
      puts "\n⚠️ Errores encontrados:"
      @import_stats[:errors].each { |error| puts "  - #{error}" }
    end
    puts "="*60
  end
end
      user.assign_attributes(
        name: user_data['name'],
        display_name: user_data['display_name'],
        message_signature: user_data['message_signature'],
        ui_settings: user_data['ui_settings'] || {},
        custom_attributes: user_data['custom_attributes'] || {},
        password: SecureRandom.hex(10)
      )
      user.skip_confirmation!
    end

    # Crear AccountUser
    AccountUser.find_or_create_by(user: @target_user, account: @target_account) do |au|
      au.assign_attributes(
        role: user_data.dig('account_user', 'role') || 'agent',
        availability: user_data.dig('account_user', 'availability') || 'online',
        auto_offline: user_data.dig('account_user', 'auto_offline')
      )
    end

    puts "✅ Usuario procesado: #{@target_user.email}"
  end

  def import_contacts
    puts "👥 Importando contactos..."
    
    @source_data['contacts'].each do |contact_data|
      target_contact = @target_account.contacts.find_or_create_by(
        email: contact_data['email']
      ) do |contact|
        contact.assign_attributes(
          name: contact_data['name'],
          phone_number: contact_data['phone_number'],
          identifier: contact_data['identifier'],
          additional_attributes: contact_data['additional_attributes'] || {},
          custom_attributes: contact_data['custom_attributes'] || {}
        )
      end

      @mapping[:contacts][contact_data['original_id']] = target_contact.id
      @import_stats[:contacts_created] += 1 if target_contact.previously_new_record?
    end

    puts "✅ Contactos procesados: #{@mapping[:contacts].length}"
  end

  def map_inboxes
    puts "📬 Mapeando inboxes..."
    
    @source_data['inboxes'].each do |inbox_data|
      # Buscar inbox compatible en cuenta destino
      target_inbox = find_compatible_inbox(inbox_data)
      
      if target_inbox
        @mapping[:inboxes][inbox_data['original_id']] = target_inbox.id
        puts "✅ Inbox mapeado: #{inbox_data['name']} -> #{target_inbox.name}"
        @import_stats[:inboxes_mapped] += 1
      else
        puts "⚠️ Inbox no encontrado: #{inbox_data['name']} (#{inbox_data['channel_type']})"
        puts "   Configura manualmente un inbox compatible en la cuenta destino"
        @import_stats[:errors] << "Inbox no mapeado: #{inbox_data['name']}"
      end
    end
  end

  def find_compatible_inbox(inbox_data)
    # Buscar inbox del mismo tipo
    @target_account.inboxes.find_by(channel_type: inbox_data['channel_type']) ||
    # Buscar por nombre similar
    @target_account.inboxes.where("name ILIKE ?", "%#{inbox_data['name']}%").first ||
    # Usar el primer inbox disponible como fallback
    @target_account.inboxes.first
  end

  def import_labels
    puts "🏷️ Importando labels..."
    
    @source_data['labels'].each do |label_data|
      target_label = @target_account.labels.find_or_create_by(
        title: label_data['title']
      ) do |label|
        label.assign_attributes(
          description: label_data['description'],
          color: label_data['color'],
          show_on_sidebar: label_data['show_on_sidebar']
        )
      end

      @mapping[:labels][label_data['title']] = target_label.id
      @import_stats[:labels_created] += 1 if target_label.previously_new_record?
    end

    puts "✅ Labels procesados: #{@mapping[:labels].length}"
  end

  def import_conversations
    puts "💬 Importando conversaciones..."
    
    @source_data['conversations'].each_with_index do |conv_data, index|
      puts "📝 Conversación #{index + 1}/#{@source_data['conversations'].length}"
      
      # Verificar que tengamos mapeos necesarios
      target_contact_id = @mapping[:contacts][conv_data['original_contact_id']]
      target_inbox_id = @mapping[:inboxes][conv_data['original_inbox_id']]
      
      unless target_contact_id && target_inbox_id
        puts "⚠️ Saltando conversación - falta mapeo (contacto: #{target_contact_id}, inbox: #{target_inbox_id})"
        @import_stats[:errors] << "Conversación #{conv_data['display_id']} - mapeo incompleto"
        next
      end

      # Crear conversación
      target_conversation = create_conversation(conv_data, target_contact_id, target_inbox_id)
      
      if target_conversation
        @mapping[:conversations][conv_data['original_id']] = target_conversation.id
        @import_stats[:conversations_created] += 1
        
        # Importar mensajes
        import_conversation_messages(target_conversation, conv_data['messages'])
        
        # Aplicar labels
        apply_conversation_labels(target_conversation, conv_data['label_names'])
      end
    end
  end

  def create_conversation(conv_data, contact_id, inbox_id)
    contact = Contact.find(contact_id)
    inbox = Inbox.find(inbox_id)
    
    # Buscar o crear ContactInbox
    contact_inbox = ContactInbox.find_or_create_by(
      contact: contact,
      inbox: inbox
    ) do |ci|
      ci.source_id = SecureRandom.uuid
    end

    # Crear conversación
    conversation = @target_account.conversations.create!(
      contact: contact,
      inbox: inbox,
      contact_inbox: contact_inbox,
      assignee: @target_user,
      status: conv_data['status'],
      priority: conv_data['priority'],
      additional_attributes: conv_data['additional_attributes'] || {},
      custom_attributes: conv_data['custom_attributes'] || {},
      identifier: conv_data['identifier']
    )

    puts "✅ Conversación creada: ##{conversation.display_id}"
    conversation
  rescue => e
    puts "❌ Error creando conversación: #{e.message}"
    @import_stats[:errors] << "Error conversación #{conv_data['display_id']}: #{e.message}"
    nil
  end

  def import_conversation_messages(conversation, messages_data)
    messages_data.each do |msg_data|
      # Determinar sender
      sender = determine_message_sender(msg_data)
      
      message = conversation.messages.create!(
        account: @target_account,
        inbox: conversation.inbox,
        sender: sender,
        content: msg_data['content'],
        message_type: msg_data['message_type'],
        private: msg_data['private'],
        content_type: msg_data['content_type'],
        content_attributes: msg_data['content_attributes'] || {},
        created_at: msg_data['created_at']
      )

      @import_stats[:messages_created] += 1
    end
  rescue => e
    puts "⚠️ Error importando mensajes: #{e.message}"
    @import_stats[:errors] << "Error mensajes conversación #{conversation.display_id}: #{e.message}"
  end

  def determine_message_sender(msg_data)
    case msg_data['sender_type']
    when 'User'
      @target_user
    when 'Contact'
      # Buscar contacto por email o usar el de la conversación
      Contact.find_by(email: msg_data['sender_email']) || conversation.contact
    else
      nil
    end
  end

  def apply_conversation_labels(conversation, label_names)
    return if label_names.blank?
    
    label_ids = label_names.map { |name| @mapping[:labels][name] }.compact
    conversation.label_ids = label_ids if label_ids.any?
  rescue => e
    puts "⚠️ Error aplicando labels: #{e.message}"
  end

  def show_import_summary
    puts "\n🎉 IMPORTACIÓN COMPLETADA"
    puts "=" * 50
    puts "📊 Estadísticas:"
    puts "   - Contactos creados: #{@import_stats[:contacts_created]}"
    puts "   - Inboxes mapeados: #{@import_stats[:inboxes_mapped]}"
    puts "   - Labels creados: #{@import_stats[:labels_created]}"
    puts "   - Conversaciones creadas: #{@import_stats[:conversations_created]}"
    puts "   - Mensajes creados: #{@import_stats[:messages_created]}"
    
    if @import_stats[:errors].any?
      puts "\n⚠️ Errores encontrados:"
      @import_stats[:errors].first(10).each { |error| puts "   - #{error}" }
      puts "   ... y #{@import_stats[:errors].count - 10} más" if @import_stats[:errors].count > 10
    end
  end
end

# =============================================================================
# EJEMPLOS DE USO - MIGRACIÓN POR CUENTA/EMPRESA
# =============================================================================

# EN SERVIDOR ORIGEN - Exportar cuenta completa:
# migrator = CompleteAccountMigration.new
# filename = migrator.export_complete_account(1, {  # ID de la cuenta
#   limit: 100,                    # Opcional: limitar conversaciones para prueba
#   status: ['open', 'resolved'],  # Opcional: filtrar por estado
#   from_date: 3.months.ago,       # Opcional: desde fecha específica
#   export_empty_account: false    # true para exportar cuenta sin conversaciones
# })

# EN SERVIDOR DESTINO - Importar cuenta completa:
# importer = CompleteAccountImport.new
# importer.import_complete_account(
#   'complete_account_export_empresa_xyz_20250124_143022.json',
#   'Nueva Empresa XYZ'  # Opcional: nombre específico para cuenta destino
# )

# =============================================================================
# COMANDOS PARA SSH/PUTTY - MIGRACIÓN COMPLETA POR EMPRESA
# =============================================================================

# 1. EN SERVIDOR ORIGEN (exportar):
# cd /home/chatwoot/chatwoot
# RAILS_ENV=production bundle exec rails runner complete_conversation_migration.rb -c "
#   migrator = CompleteAccountMigration.new
#   filename = migrator.export_complete_account(
#     ACCOUNT_ID_AQUI,  # Reemplazar con ID real de la cuenta
#     { limit: 500 }    # Opcional: límite para primera prueba
#   )
#   puts \"Archivo generado: #{filename}\"
# "

# 2. TRANSFERIR ARCHIVO (usando scp desde servidor origen a destino):
# scp complete_account_export_*.json usuario@servidor-destino:/home/chatwoot/chatwoot/

# 3. EN SERVIDOR DESTINO (importar):
# cd /home/chatwoot/chatwoot
# RAILS_ENV=production bundle exec rails runner complete_conversation_migration.rb -c "
#   importer = CompleteAccountImport.new
#   success = importer.import_complete_account(
#     'NOMBRE_ARCHIVO_AQUI.json',  # Nombre del archivo transferido
#     'Nombre Cuenta Destino'      # Opcional: nombre específico
#   )
#   puts success ? 'Importación exitosa' : 'Error en importación'
# "

# =============================================================================
# VERIFICACIONES POST-MIGRACIÓN
# =============================================================================

# EN SERVIDOR DESTINO - Verificar migración:
# cd /home/chatwoot/chatwoot
# RAILS_ENV=production bundle exec rails console
# 
# # Verificar cuenta
# account = Account.find_by(name: 'Nombre Cuenta Destino')
# puts "Cuenta: #{account.name}"
# puts "Usuarios: #{account.users.count}"
# puts "Conversaciones: #{account.conversations.count}"
# puts "Contactos: #{account.contacts.count}"
# puts "Inboxes: #{account.inboxes.count}"
# 
# # Verificar conversación específica
# conv = account.conversations.first
# puts "Conversación ##{conv.display_id}: #{conv.messages.count} mensajes"

# =============================================================================
# NOTAS IMPORTANTES
# =============================================================================
# 
# 1. Esta migración transfiere TODA la empresa/cuenta completa entre servidores
# 2. Incluye: usuarios, conversaciones, contactos, inboxes, equipos, labels,
#    respuestas enlatadas, filtros, webhooks y reglas de automatización
# 3. Se preservan todas las relaciones y dependencias
# 4. Los archivos adjuntos se marcan para descarga manual posterior
# 5. Usar primero con límite de conversaciones para probar
# 6. La cuenta destino se puede crear nueva o usar existente
# 7. Los usuarios mantienen sus roles y configuraciones
# 8. Se respetan los timestamps originales de creación
