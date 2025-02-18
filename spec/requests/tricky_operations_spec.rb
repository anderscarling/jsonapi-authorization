require 'spec_helper'

RSpec.describe 'Tricky operations', type: :request do
  include AuthorizationStubs
  fixtures :all

  let(:article) { Article.all.sample }
  let(:article_policy_scope) { Article.none }
  let(:comments_policy_scope) { Comment.none }

  subject { last_response }
  let(:json_data) { JSON.parse(last_response.body)["data"] }

  before do
    allow_any_instance_of(ArticlePolicy::Scope).to receive(:resolve).and_return(article_policy_scope)
    allow_any_instance_of(CommentPolicy::Scope).to receive(:resolve).and_return(comments_policy_scope)
  end

  before do
    header 'Content-Type', 'application/vnd.api+json'
  end

  describe 'POST /comments (with relationships link to articles)' do
    subject(:last_response) { post("/comments", json) }
    let(:json) do
      <<-EOS.strip_heredoc
      {
        "data": {
          "type": "comments",
          "relationships": {
            "article": {
              "data": {
                "id": "#{article.external_id}",
                "type": "articles"
              }
            }
          }
        }
      }
      EOS
    end
    let(:related_records_with_context) do
      [{
        relation_name: :article,
        relation_type: :to_one,
        records: article
      }]
    end

    context 'authorized for create_resource on Comment and newly associated article' do
      let(:article_policy_scope) { Article.where(id: article.id) }
      before { allow_operation('create_resource', source_class: Comment, related_records_with_context: related_records_with_context) }

      it { is_expected.to be_successful }
    end

    context 'unauthorized for create_resource on Comment and newly associated article' do
      let(:article_policy_scope) { Article.where(id: article.id) }
      before { disallow_operation('create_resource', source_class: Comment, related_records_with_context: related_records_with_context) }

      it { is_expected.to be_forbidden }

      context 'which is out of scope' do
        let(:article_policy_scope) { Article.none }

        it { is_expected.to be_not_found }
      end
    end
  end

  describe 'POST /articles (with relationships link to comments)' do
    let!(:new_comments) do
      Array.new(2) { Comment.create }
    end
    let(:related_records_with_context) do
      [{
        relation_name: :comments,
        relation_type: :to_many,
        records: new_comments
      }]
    end
    let(:comments_policy_scope) { Comment.all }

    let(:json) do
      <<-EOS.strip_heredoc
      {
        "data": {
          "id": "new-article-id",
          "type": "articles",
          "relationships": {
            "comments": {
              "data": [
                { "id": "#{new_comments[0].id}", "type": "comments" },
                { "id": "#{new_comments[1].id}", "type": "comments" }
              ]
            }
          }
        }
      }
      EOS
    end
    subject(:last_response) { post("/articles", json) }

    context 'authorized for create_resource on Article and newly associated comments' do
      let(:article_policy_scope) { Article.where(id: "new-article-id") }
      before { allow_operation('create_resource', source_class: Article, related_records_with_context: related_records_with_context) }

      it { is_expected.to be_successful }
    end

    context 'unauthorized for create_resource on Article and newly associated comments' do
      let(:article_policy_scope) { Article.where(id: "new-article-id") }
      before { disallow_operation('create_resource', source_class: Article, related_records_with_context: related_records_with_context) }

      it { is_expected.to be_forbidden }
    end
  end

  describe 'POST /tags (with polymorphic relationship link to article)' do
    subject(:last_response) { post("/tags", json) }
    let(:json) do
      <<-EOS.strip_heredoc
      {
        "data": {
          "type": "tags",
          "relationships": {
            "taggable": {
              "data": {
                "id": "#{article.external_id}",
                "type": "articles"
              }
            }
          }
        }
      }
      EOS
    end

    let(:related_records_with_context) do
      [{
        relation_name: :taggable,
        relation_type: :to_one,
        records: article
      }]
    end

    context 'authorized for create_resource on Tag and newly associated article' do
      let(:article_policy_scope) { Article.where(id: article.id) }
      before { allow_operation('create_resource', source_class: Tag, related_records_with_context: related_records_with_context) }

      it { is_expected.to be_successful }
    end

    context 'unauthorized for create_resource on Tag and newly associated article' do
      let(:article_policy_scope) { Article.where(id: article.id) }
      before { disallow_operation('create_resource', source_class: Tag, related_records_with_context: related_records_with_context) }

      it { is_expected.to be_forbidden }

      context 'which is out of scope' do
        let(:article_policy_scope) { Article.none }

        it { is_expected.to be_not_found }
      end
    end
  end

  describe 'PATCH /articles/:id (mass-modifying relationships)' do
    let!(:new_comments) do
      Array.new(2) { Comment.create }
    end
    let(:related_records_with_context) do
      [{
        relation_name: :comments,
        relation_type: :to_many,
        records: new_comments
      }]
    end
    let(:article_policy_scope) { Article.where(id: article.id) }
    let(:comments_policy_scope) { Comment.all }
    before do
      allow_any_instance_of(CommentPolicy::Scope).to receive(:resolve).and_return(comments_policy_scope)
    end

    let(:json) do
      <<-EOS.strip_heredoc
      {
        "data": {
          "id": "#{article.external_id}",
          "type": "articles",
          "relationships": {
            "comments": {
              "data": [
                { "type": "comments", "id": "#{new_comments.first.id}" },
                { "type": "comments", "id": "#{new_comments.second.id}" }
              ]
            }
          }
        }
      }
      EOS
    end
    subject(:last_response) { patch("/articles/#{article.external_id}", json) }

    context 'authorized for replace_fields on article and all new records' do
      context 'not limited by Comments policy scope' do
        before { allow_operation('replace_fields', source_record: article, related_records_with_context: related_records_with_context) }
        it { is_expected.to be_successful }
      end

      context 'limited by Comments policy scope' do
        let(:comments_policy_scope) { Comment.where("id NOT IN (?)", new_comments.map(&:id)) }
        let(:related_records_with_context) do
          [{
            relation_name: :comments,
            relation_type: :to_many,
            records: new_comments
          }]
        end
        before { disallow_operation('replace_fields', source_record: article, related_records_with_context: related_records_with_context) }

        it { is_expected.to be_not_found }
      end
    end

    context 'unauthorized for replace_fields on article and all new records' do
      before { disallow_operation('replace_fields', source_record: article, related_records_with_context: related_records_with_context) }

      it { is_expected.to be_forbidden }
    end
  end

  describe 'PATCH /articles/:id (nullifying to-one relationship)' do
    let(:article) { articles(:article_with_author) }
    let(:json) do
      <<-EOS.strip_heredoc
      {
        "data": {
          "id": "#{article.external_id}",
          "type": "articles",
          "relationships": { "author": null }
        }
      }
      EOS
    end
    let(:article_policy_scope) { Article.all }
    subject(:last_response) { patch("/articles/#{article.external_id}", json) }

    before do
      allow_operation(
        'replace_fields',
        source_record: article,
        related_records_with_context: [{ relation_type: :to_one, relation_name: :author, records: nil }]
      )
    end

    it { is_expected.to be_successful }
  end
end
