require 'spec_helper'

describe LeaderRequirements do

  let(:user) { Fabricate.build(:user) }
  subject(:leader_requirements) { described_class.new(user) }

  before do
    described_class.clear_cache
  end

  def make_view(id, at, user_id)
    TopicViewItem.add(id, '11.22.33.44', user_id, at)
  end

  describe "requirements" do
    it "min_days_visited uses site setting" do
      SiteSetting.stubs(:leader_requires_days_visited).returns(66)
      leader_requirements.min_days_visited.should == 66
    end

    it "min_topics_replied_to uses site setting" do
      SiteSetting.stubs(:leader_requires_topics_replied_to).returns(12)
      leader_requirements.min_topics_replied_to.should == 12
    end

    it "min_topics_viewed depends on site setting and number of topics created" do
      SiteSetting.stubs(:leader_requires_topics_viewed).returns(75)
      described_class.stubs(:num_topics_in_time_period).returns(31)
      leader_requirements.min_topics_viewed.should == 23
    end

    it "min_posts_read depends on site setting and number of posts created" do
      SiteSetting.stubs(:leader_requires_posts_read).returns(66)
      described_class.stubs(:num_posts_in_time_period).returns(1234)
      leader_requirements.min_posts_read.should == 814
    end

    it "min_topics_viewed_all_time depends on site setting" do
      SiteSetting.stubs(:leader_requires_topics_viewed_all_time).returns(75)
      leader_requirements.min_topics_viewed_all_time.should == 75
    end

    it "min_posts_read_all_time depends on site setting" do
      SiteSetting.stubs(:leader_requires_posts_read_all_time).returns(1001)
      leader_requirements.min_posts_read_all_time.should == 1001
    end

    it "max_flagged_posts depends on site setting" do
      SiteSetting.stubs(:leader_requires_max_flagged).returns(3)
      leader_requirements.max_flagged_posts.should == 3
    end

    it "min_likes_given depends on site setting" do
      SiteSetting.stubs(:leader_requires_likes_given).returns(30)
      leader_requirements.min_likes_given.should == 30
    end

    it "min_likes_received depends on site setting" do
      SiteSetting.stubs(:leader_requires_likes_received).returns(20)
      leader_requirements.min_likes_received.should == 20
    end
  end

  describe "days_visited" do
    it "counts visits when posts were read no further back than 100 days ago" do
      user.save
      user.update_posts_read!(1, 2.days.ago)
      user.update_posts_read!(1, 3.days.ago)
      user.update_posts_read!(0, 4.days.ago)
      user.update_posts_read!(3, 101.days.ago)
      leader_requirements.days_visited.should == 2
    end
  end

  describe "num_topics_replied_to" do
    it "counts topics in which user replied in last 100 days" do
      user.save

      not_a_reply = create_post(user: user) # user created the topic, so it doesn't count

      topic1      = create_post.topic
      reply1      = create_post(topic: topic1, user: user)
      reply_again = create_post(topic: topic1, user: user) # two replies in one topic

      topic2      = create_post(created_at: 101.days.ago).topic
      reply2      = create_post(topic: topic2, user: user, created_at: 101.days.ago) # topic is over 100 days old

      leader_requirements.num_topics_replied_to.should == 1
    end
  end

  describe "topics_viewed" do
    it "counts topics views within last 100 days, not counting a topic more than once" do
      user.save
      make_view(9, 1.day.ago,    user.id)
      make_view(9, 3.days.ago,   user.id) # same topic, different day
      make_view(3, 4.days.ago,   user.id)
      make_view(2, 101.days.ago, user.id) # too long ago
      leader_requirements.topics_viewed.should == 2
    end
  end

  describe "posts_read" do
    it "counts posts read within the last 100 days" do
      user.save
      user.update_posts_read!(3, 2.days.ago)
      user.update_posts_read!(1, 3.days.ago)
      user.update_posts_read!(0, 4.days.ago)
      user.update_posts_read!(5, 101.days.ago)
      leader_requirements.posts_read.should == 4
    end
  end

  describe "topics_viewed_all_time" do
    it "counts topics viewed at any time" do
      user.save
      make_view(10, 1.day.ago,    user.id)
      make_view(9,  100.days.ago, user.id)
      make_view(8,  101.days.ago, user.id)
      leader_requirements.topics_viewed_all_time.should == 3
    end
  end

  describe "posts_read_all_time" do
    it "counts posts read at any time" do
      user.save
      user.update_posts_read!(3, 2.days.ago)
      user.update_posts_read!(1, 101.days.ago)
      leader_requirements.posts_read_all_time.should == 4
    end
  end

  context "with flagged posts" do
    before do
      user.save
      flags = [:off_topic, :inappropriate, :notify_user, :notify_moderators, :spam].map do |t|
        Fabricate(:flag, post: Fabricate(:post, user: user), post_action_type_id: PostActionType.types[t], agreed_at: 1.minute.ago)
      end

      deferred_flags = [:off_topic, :inappropriate, :notify_user, :notify_moderators, :spam].map do |t|
        Fabricate(:flag, post: Fabricate(:post, user: user), post_action_type_id: PostActionType.types[t], deferred_at: 1.minute.ago)
      end

      deleted_flags = [:off_topic, :inappropriate, :notify_user, :notify_moderators, :spam].map do |t|
        Fabricate(:flag, post: Fabricate(:post, user: user), post_action_type_id: PostActionType.types[t], deleted_at: 1.minute.ago)
      end

      # Same post, different user:
      Fabricate(:flag, post: flags[1].post, post_action_type_id: PostActionType.types[:spam], agreed_at: 1.minute.ago)

      # Flagged their own post:
      Fabricate(:flag, user: user, post: Fabricate(:post, user: user), post_action_type_id: PostActionType.types[:spam], agreed_at: 1.minute.ago)

      # More than 100 days ago:
      Fabricate(:flag, post: Fabricate(:post, user: user, created_at: 101.days.ago), post_action_type_id: PostActionType.types[:spam], created_at: 101.days.ago, agreed_at: 1.day.ago)
    end

    it "num_flagged_posts and num_flagged_by_users count spam and inappropriate agreed flags in the last 100 days" do
      leader_requirements.num_flagged_posts.should == 2
      leader_requirements.num_flagged_by_users.should == 3
    end
  end

  describe "num_likes_given" do
    it "counts likes given in the last 100 days" do
      ActiveRecord::Base.observers.enable :user_action_observer

      recent_post1 = create_post(created_at: 1.hour.ago)
      recent_post2 = create_post(created_at: 10.days.ago)
      old_post     = create_post(created_at: 102.days.ago)

      Fabricate(:like, user: user, post: recent_post1, created_at: 2.hours.ago)
      Fabricate(:like, user: user, post: recent_post2, created_at: 5.days.ago)
      Fabricate(:like, user: user, post: old_post,     created_at: 101.days.ago)

      leader_requirements.num_likes_given.should == 2
    end
  end

  describe "num_likes_received" do
    it "counts likes received in the last 100 days" do
      ActiveRecord::Base.observers.enable :user_action_observer

      t = Fabricate(:topic, user: user, created_at: 102.days.ago)
      old_post     = create_post(topic: t, user: user, created_at: 102.days.ago)
      recent_post2 = create_post(topic: t, user: user, created_at: 10.days.ago)
      recent_post1 = create_post(topic: t, user: user, created_at: 1.hour.ago)

      liker = Fabricate(:user)
      Fabricate(:like, user: liker, post: recent_post1, created_at: 2.hours.ago)
      Fabricate(:like, user: liker, post: recent_post2, created_at: 5.days.ago)
      Fabricate(:like, user: liker, post: old_post,     created_at: 101.days.ago)

      leader_requirements.num_likes_received.should == 2
    end
  end

  describe "requirements" do

    before do
      leader_requirements.stubs(:min_days_visited).returns(50)
      leader_requirements.stubs(:min_topics_replied_to).returns(10)
      leader_requirements.stubs(:min_topics_viewed).returns(25)
      leader_requirements.stubs(:min_posts_read).returns(25)
      leader_requirements.stubs(:min_topics_viewed_all_time).returns(200)
      leader_requirements.stubs(:min_posts_read_all_time).returns(500)
      leader_requirements.stubs(:max_flagged_posts).returns(5)
      leader_requirements.stubs(:max_flagged_by_users).returns(5)
      leader_requirements.stubs(:min_likes_given).returns(30)
      leader_requirements.stubs(:min_likes_received).returns(20)

      leader_requirements.stubs(:days_visited).returns(50)
      leader_requirements.stubs(:num_topics_replied_to).returns(10)
      leader_requirements.stubs(:topics_viewed).returns(25)
      leader_requirements.stubs(:posts_read).returns(25)
      leader_requirements.stubs(:topics_viewed_all_time).returns(200)
      leader_requirements.stubs(:posts_read_all_time).returns(500)
      leader_requirements.stubs(:num_flagged_posts).returns(0)
      leader_requirements.stubs(:num_flagged_by_users).returns(0)
      leader_requirements.stubs(:num_likes_given).returns(30)
      leader_requirements.stubs(:num_likes_received).returns(20)
    end

    it "are met when all requirements are met" do
      leader_requirements.requirements_met?.should == true
    end

    it "are not met if too few days visited" do
      leader_requirements.stubs(:days_visited).returns(49)
      leader_requirements.requirements_met?.should == false
    end

    it "are not lost if requirements are close" do
      leader_requirements.stubs(:days_visited).returns(45)
      leader_requirements.stubs(:num_topics_replied_to).returns(9)
      leader_requirements.stubs(:topics_viewed).returns(23)
      leader_requirements.stubs(:posts_read).returns(23)
      leader_requirements.stubs(:num_likes_given).returns(29)
      leader_requirements.stubs(:num_likes_received).returns(19)
      leader_requirements.requirements_lost?.should == false
    end

    it "are lost if not enough visited" do
      leader_requirements.stubs(:days_visited).returns(44)
      leader_requirements.requirements_lost?.should == true
    end

    it "are lost if not enough topics replied to" do
      leader_requirements.stubs(:num_topics_replied_to).returns(8)
      leader_requirements.requirements_lost?.should == true
    end

    it "are lost if not enough topics viewed" do
      leader_requirements.stubs(:topics_viewed).returns(22)
      leader_requirements.requirements_lost?.should == true
    end

    it "are lost if not enough posts read" do
      leader_requirements.stubs(:posts_read).returns(22)
      leader_requirements.requirements_lost?.should == true
    end

    it "are not met if not enough likes given" do
      leader_requirements.stubs(:num_likes_given).returns(29)
      leader_requirements.requirements_met?.should == false
    end

    it "are not met if not enough likes received" do
      leader_requirements.stubs(:num_likes_received).returns(19)
      leader_requirements.requirements_met?.should == false
    end

    it "are lost if not enough likes given" do
      leader_requirements.stubs(:num_likes_given).returns(26)
      leader_requirements.requirements_lost?.should == true
    end

    it "are lost if not enough likes received" do
      leader_requirements.stubs(:num_likes_received).returns(17)
      leader_requirements.requirements_lost?.should == true
    end

    it "are not met if suspended" do
      user.stubs(:suspended?).returns(true)
      leader_requirements.requirements_met?.should == false
    end

    it "are lost if suspended" do
      user.stubs(:suspended?).returns(true)
      leader_requirements.requirements_lost?.should == true
    end
  end

end
