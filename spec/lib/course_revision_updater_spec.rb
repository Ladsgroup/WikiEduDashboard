# frozen_string_literal: true
require 'rails_helper'
require "#{Rails.root}/lib/course_revision_updater"

describe CourseRevisionUpdater do
  describe 'imported revisions and articles' do
    let(:course) { create(:course, id: 1, start: '2016-03-20', end: '2016-03-31') }
    let(:user) { create(:user, username: 'Tedholtby') }
    let(:courses_user) do
      create(:courses_user, course_id: 1, user_id: user.id,
                            role: CoursesUsers::Roles::STUDENT_ROLE)
    end

    let(:revision_import) do
      course && user && courses_user
      CourseRevisionUpdater.import_new_revisions(Course.all)
    end

    it 'includes the correct article and revision data' do
      revision_import
      expected_article = Article.find_by(wiki_id: 1,
                                         title: '1978_Revelation_on_Priesthood',
                                         mw_page_id: 15124285,
                                         namespace: 0)

      expected_revision = Revision.find_by(mw_rev_id: 712907095,
                                           user_id: user.id,
                                           wiki_id: 1,
                                           mw_page_id: 15124285,
                                           characters: 579,
                                           article_id: expected_article.id)
      expect(expected_revision).to be_a(Revision)
    end

    it 'updates article title if it does not match existing article record' do
      create(:article, id: 15124285, mw_page_id: 15124285, wiki_id: 1, title: 'foo')

      revision_import

      expect(Article.find_by(mw_page_id: 15124285).title).to eq('1978_Revelation_on_Priesthood')
      expect(Article.where(mw_page_id: 15124285).count).to eq(1)
    end
  end

  describe '.import_new_revisions' do
    context 'when the course is not current but "needs_update" is true' do
      let(:course) { create(:course, start: '2016-03-20', end: '2016-03-31', needs_update: true) }
      let(:user) { create(:user) }
      let!(:student) { create(:courses_user, user_id: user.id, course_id: course.id) }

      it 'updates and sets `needs_update` to false' do
        expect_any_instance_of(CourseRevisionUpdater)
          .to receive(:update_revisions_for_relevant_wikis)
        expect(Course.current).not_to include(course)
        CourseRevisionUpdater.import_new_revisions
        expect(course.reload.needs_update).to eq(false)
      end
    end

    it 'fetches revisions for existing courses' do
      VCR.use_cassette 'revisions/update_all_revisions' do
        # Try it with no courses.
        CourseRevisionUpdater.import_new_revisions
        expect(Revision.all.count).to eq(0)

        # Now add a course with users
        VCR.use_cassette 'wiki/course_data' do
          LegacyCourseImporter.update_all_courses(false, campaign: [351])
        end

        CourseRevisionUpdater.import_new_revisions(Course.all)
        # When the non-students are included, Revisions count is 1919.
        expect(Revision.all.count).to eq(519)
        # When the non-students are included, ArticlesCourses count is 224.
        expect(ArticlesCourses.all.count).to eq(10)

        # Update the revision counts, then try update_all_revisions again
        # to test how it handles old users.
        CourseRevisionUpdater.import_new_revisions(Course.all)
        expect(Revision.all.count).to eq(519)
        expect(ArticlesCourses.all.count).to eq(10)
      end
    end

    it 'includes revisions on the final day of a course up to the end time' do
      create(:course, id: 1, start: '2016-03-20', end: '2016-03-31'.to_date.end_of_day)
      create(:user, id: 1, username: 'Tedholtby')
      create(:courses_user, course_id: 1,
                            user_id: 1,
                            role: CoursesUsers::Roles::STUDENT_ROLE)

      CourseRevisionUpdater.import_new_revisions(Course.all)

      expect(User.find(1).revisions.count).to eq(3)
      expect(Course.find(1).revisions.count).to eq(3)
    end

    it 'imports revisions soon after the final day of the course, but excludes them from metrics' do
      create(:course, id: 1, start: '2016-03-20', end: '2016-03-30')
      create(:user, id: 15, username: 'Tedholtby')
      create(:courses_user, course_id: 1, user_id: 15,
                            role: CoursesUsers::Roles::STUDENT_ROLE)

      CourseRevisionUpdater.import_new_revisions(Course.all)

      expect(User.find(15).revisions.count).to eq(3)
      expect(Course.find(1).revisions.count).to eq(0)
    end

    it 'handles returning users with earlier revisions' do
      VCR.use_cassette 'revisions/returning_students' do
        # Create a user who has a revision from long ago
        create(:trained, id: 5) # This is user Ragesoss, with edits since 2015.
        create(:revision,
               user_id: 5,
               article_id: 1,
               date: '2013-01-01'.to_date)
        # Also a revision from during the course.
        create(:revision,
               user_id: 5,
               article_id: 2,
               date: '2015-02-01'.to_date)
        create(:article, id: 1)
        create(:article, id: 2)
        # Create a recent course and add the user to it.
        create(:course,
               id: 1,
               start: '2015-01-01'.to_date,
               end: '2030-01-01'.to_date)
        create(:courses_user,
               course_id: 1,
               user_id: 5,
               role: 0)
        CoursesUsers.update_all_caches
        CourseRevisionUpdater.import_new_revisions(Course.all)
        expect(Revision.all.count > 1).to be true
      end
    end
  end
end
