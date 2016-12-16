#-- encoding: UTF-8
#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2015 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

class Queries::BaseFilter
  include ActiveModel::Validations
  include Queries::SqlForField

  class_attribute :model,
                  :filter_params,
                  :operators,
                  :operators_not_requiring_values,
                  :operators_by_filter_type

  self.filter_params = [:operator, :values]

  self.operators = {
    label_equals:               '=',
    label_not_equals:           '!',
    label_open_work_packages:   'o',
    label_closed_work_packages: 'c',
    label_none:                 '!*',
    label_all:                  '*',
    label_greater_or_equal:     '>=',
    label_less_or_equal:        '<=',
    label_in_less_than:         '<t+',
    label_in_more_than:         '>t+',
    label_in:                   't+',
    label_today:                't',
    label_this_week:            'w',
    label_less_than_ago:        '>t-',
    label_more_than_ago:        '<t-',
    label_ago:                  't-',
    label_contains:             '~',
    label_not_contains:         '!~'
  }.invert

  self.operators_not_requiring_values = %w(o c !* * t w)

  self.operators_by_filter_type = {
    list:             ['=', '!'],
    list_status:      ['o', '=', '!', 'c', '*'],
    list_optional:    ['=', '!', '!*', '*'],
    list_subprojects: ['*', '!*', '='],
    date:             ['<t+', '>t+', 't+', 't', 'w', '>t-', '<t-', 't-'],
    date_past:        ['>t-', '<t-', 't-', 't', 'w'],
    string:           ['=', '~', '!', '!~'],
    text:             ['~', '!~'],
    integer:          ['=', '!', '>=', '<=', '!*', '*']
  }

  attr_accessor :context,
                *filter_params

  def initialize(options = {})
    self.context = options[:context]

    self.class.filter_params.each do |param_field|
      send("#{param_field}=", options[param_field])
    end
  end

  def [](name)
    send(name)
  end

  def name
    @name || self.class.key
  end
  alias :field :name

  def name=(name)
    @name = name.to_sym
  end

  def human_name
    raise NotImplementedError
  end

  def type
    raise NotImplementedError
  end

  def allowed_values
    nil
  end

  def available?
    true
  end

  def scope
    scope = model.where(where)
    scope = scope.joins(joins) if joins
    scope
  end

  def self.key
    to_s.demodulize.underscore.gsub(/_filter$/, '').to_sym
  end

  def self.connection
    model.connection
  end

  def self.all_for(context = nil)
    filter = new
    filter.context = context
    filter
  end

  def where
    sql_for_field(self.class.key, operator, values, self.class.model.table_name, self.class.key)
  end

  def joins
    nil
  end

  validate :validate_inclusion_of_operator
  validate :validate_presence_of_values,
           unless: Proc.new { |filter| operators_not_requiring_values.include?(filter.operator) }
  validate :validate_filter_values

  def values
    @values || []
  end

  def values=(values)
    @values = Array(values).reject(&:blank?).map(&:to_s)
  end

  protected

  def validate_inclusion_of_operator
    unless self.class.operators_by_filter_type[type].include? operator
      errors.add(:operator, :inclusion)
    end
  end

  def validate_presence_of_values
    if values.nil? || values.reject(&:blank?).empty?
      errors.add(:values, I18n.t('activerecord.errors.messages.blank'))
    end
  end

  def validate_filter_values
    return true if self.class.operators_not_requiring_values.include?(operator)

    case type
    when :integer, :date, :date_past
      validate_values_all_integer
    when :list, :list_optional
      validate_values_in_allowed_values_list
    end
  end

  def validate_values_all_integer
    unless values.all? { |value| integer?(value) }
      errors.add(:values, I18n.t('activerecord.errors.messages.not_an_integer'))
    end
  end

  def validate_values_in_allowed_values_list
    # TODO: the -1 is a special value that exists for historical reasons
    # so one can send the operator '=' and the values ['-1']
    # which results in a IS NULL check in the DB
    if (values & (allowed_values.map(&:last).map(&:to_s) + ['-1'])) != values
      errors.add(:values, :inclusion)
    end
  end

  def integer?(str)
    true if Integer(str)
  rescue
    false
  end
end
