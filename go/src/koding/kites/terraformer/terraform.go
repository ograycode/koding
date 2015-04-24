package terraformer

import (
	"koding/kites/terraformer/kodingcontext"
	"runtime/debug"
	"strings"

	"github.com/hashicorp/terraform/terraform"
	"github.com/koding/kite"
	"github.com/koding/logging"
	"github.com/koding/metrics"
)

var (
	Name    = "terraformer"
	Version = "0.0.1"
)

type Terraformer struct {
	// Log is a specialized log system for terraform
	Log logging.Logger

	// Metrics holds the metric aggregator
	Metrics *metrics.DogStatsD

	// Enable debug mode
	Debug bool

	// Context holds the initial context, all usages should clone it
	Context *kodingcontext.Context
}

type TerraformRequest struct {
	Content   string
	Variables map[string]string
	ContentID string
}

func New() *Terraformer { return &Terraformer{} }

func (t *Terraformer) Plan(r *kite.Request) (plan interface{}, err error) {
	defer func() {
		if err != nil {
			debug.PrintStack()
		}
	}()

	c := t.Context.Clone()
	defer c.Close()

	plan, err = t.plan(c, r, false)
	if err != nil {
		return nil, err
	}

	return plan, nil
}

func (t *Terraformer) Apply(r *kite.Request) (interface{}, error) {
	c := t.Context.Clone()
	defer c.Close()

	plan, err := t.apply(c, r, false)
	if err != nil {
		return nil, err
	}

	return plan, nil
}

func (t *Terraformer) Destroy(r *kite.Request) (interface{}, error) {
	c := t.Context.Clone()
	defer c.Close()

	plan, err := t.apply(c, r, true)
	if err != nil {
		return nil, err
	}

	return plan, nil
}

func (t *Terraformer) context(
	c *kodingcontext.Context,
	r *kite.Request,
	destroy bool,
) (*terraform.Context, error) {
	// get the plan
	plan, err := t.plan(c, r, destroy)
	if err != nil {
		return nil, err
	}

	// create terraform context options from plan
	copts := c.TerraformContextOptsWithPlan(plan)

	// create terraform context with its options
	return terraform.NewContext(copts), nil
}

func (t *Terraformer) plan(
	c *kodingcontext.Context,
	r *kite.Request,
	destroy bool,
) (*terraform.Plan, error) {
	args := TerraformRequest{}
	if err := r.Args.One().Unmarshal(&args); err != nil {
		return nil, err
	}

	c.Variables = args.Variables
	c.ContentID = args.ContentID

	content := strings.NewReader(args.Content)
	return c.Plan(content, destroy)
}

func (t *Terraformer) apply(
	c *kodingcontext.Context,
	r *kite.Request,
	destroy bool,
) (*terraform.Plan, error) {
	args := TerraformRequest{}
	if err := r.Args.One().Unmarshal(&args); err != nil {
		return nil, err
	}

	c.Variables = args.Variables
	c.ContentID = args.ContentID

	content := strings.NewReader(args.Content)
	return c.Apply(content, destroy)
}
