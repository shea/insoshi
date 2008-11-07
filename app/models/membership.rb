class Membership < ActiveRecord::Base
  extend ActivityLogger
  extend PreferencesHelper
  
  belongs_to :group
  belongs_to :person
  has_many :activities, :foreign_key => "item_id" #, :dependent => :destroy
  validates_presence_of :person_id, :group_id
  
  # Status codes.
  ACCEPTED  = 0
  INVITED   = 1
  PENDING   = 2
  
  # Accept a membership request (instance method).
  def accept
    Membership.accept(person_id, group_id)
  end
  
  def breakup
    Membership.breakup(person_id, group_id)
  end
  
  class << self
    
    # Return true if the person is member of the group.
    def exists?(person, group)
      not mem(person, group).nil?
    end
    
    alias exist? exists?
    
    # Make a pending membership request.
    def request(person, group, send_mail = nil)
      if send_mail.nil?
        send_mail = global_prefs.email_notifications? &&
                    group.owner.connection_notifications?
      end
      if person.groups.include?(group) or Membership.exists?(person, group)
        nil
      else
        if group.public? or group.private?
          transaction do
            create(:person => person, :group => group, :status => PENDING)
          end
          if group.public?
            membership = person.memberships.find(:first, :conditions => ['group_id = ?',group])
            membership.accept
          end
        end
#        if send_mail
#          # The order here is important: the mail is sent *to* the contact,
#          # so the connection should be from the contact's point of view.
#          connection = conn(contact, person)
#          PersonMailer.deliver_connection_request(connection)
#        end
        true
      end
    end
    
    def invite(person, group, send_mail = nil)
      if send_mail.nil?
        send_mail = global_prefs.email_notifications? &&
                    group.owner.connection_notifications?
      end
      if person.groups.include?(group) or Membership.exists?(person, group)
        nil
      else
        transaction do
          create(:person => person, :group => group, :status => INVITED)
        end
#        if send_mail
#          # The order here is important: the mail is sent *to* the contact,
#          # so the connection should be from the contact's point of view.
#          connection = conn(contact, person)
#          PersonMailer.deliver_connection_request(connection)
#        end
        true
      end
    end
    
    # Accept a membership request.
    def accept(person, group)
      transaction do
        accepted_at = Time.now
        accept_one_side(person, group, accepted_at)
      end
      unless Group.find(group).hidden?
        log_activity(mem(person, group))
      end
    end
    
    def breakup(person, group)
      transaction do
        destroy(mem(person, group))
#        destroy(conn(contact, person))
      end
    end
    
    def mem(person, group)
      find_by_person_id_and_group_id(person, group)
    end
    
    def accepted?(person, group)
      mem(person, group).status == ACCEPTED
    end
    
    def connected?(person, group)
      exist?(person, group) and accepted?(person, group)
    end
    
    def pending?(person, group)
      exist?(person, group) and mem(person,group).status == PENDING
    end
    
    def invited?(person, group)
      exist?(person, group) and mem(person,group).status == INVITED
    end
    
  end
  
  private
  
  class << self
    # Update the db with one side of an accepted connection request.
    def accept_one_side(person, group, accepted_at)
      mem = mem(person, group)
      mem.update_attributes!(:status => ACCEPTED,
                              :accepted_at => accepted_at)
    end
  
    def log_activity(membership)
      activity = Activity.create!(:item => membership, :person => membership.person)
      add_activities(:activity => activity, :person => membership.person)
    end
  end
  
end
